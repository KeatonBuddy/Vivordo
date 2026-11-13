"use strict";
/* eslint-disable require-jsdoc */
// Calendar invites between Circle friends. Clients only read
// event_invites/{id}; every write comes through these callables, which
// check friendships and blocks the way createChallenge does.
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {Timestamp} = require("firebase-admin/firestore");
const {pushToUser, shortName} = require("./push");
const {requireBudget} = require("./rate_limit");

// Profile photos are uploaded to the app's own storage; anything else in
// the (owner-written) profile isn't passed on for friends' phones to load.
const ownPhoto = (url) => typeof url === "string" &&
  url.startsWith("https://firebasestorage.googleapis.com/") ? url : null;

const MAX_RECIPIENTS = 20;
const MAX_TITLE_LENGTH = 200;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_LENGTH_MS = 7 * DAY_MS;
const MAX_AHEAD_MS = 366 * DAY_MS;
const OPEN_SERIES_MS = 183 * DAY_MS;
const MAX_EXCEPTIONS = 100;

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }
  return request.auth.uid;
}

function stringId(value, name) {
  const id = typeof value === "string" ? value.trim() : "";
  if (!id || id.includes("/") || id.length > 1500) {
    throw new HttpsError("invalid-argument", `${name} is required.`);
  }
  return id;
}

/**
 * The event fields a sender may set: title, start/end (epoch ms), allDay.
 * @param {object} data Callable data.
 * @param {number} now Epoch ms.
 * @return {object} {title, start, end, allDay}.
 */
function validatedEventFields(data, now) {
  const title = typeof data?.title === "string" ? data.title.trim() : "";
  if (!title || title.length > MAX_TITLE_LENGTH) {
    throw new HttpsError("invalid-argument", "The event needs a title.");
  }
  const start = Number(data?.start);
  const end = Number(data?.end);
  const recurrence = validatedRecurrence(data?.recurrence);
  // A series is still on until its last occurrence; start/end are its first.
  const until = recurrence ? Math.max(seriesEnd(recurrence, start), end) : end;
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
      end - start > MAX_LENGTH_MS || until < now ||
      start > now + MAX_AHEAD_MS) {
    throw new HttpsError("invalid-argument", "Choose a valid event time.");
  }
  return {title, start, end, allDay: data?.allDay === true, recurrence, until};
}

/**
 * The repeat rule of a repeating event (a Google-style RRULE line), or null
 * for a one-off.
 * @param {*} value Callable input.
 * @return {string|null} The rule.
 */
function validatedRecurrence(value) {
  if (value == null || value === "none") return null;
  if (typeof value !== "string" || value.length > 300 ||
      !/^RRULE:[A-Z0-9=;,]+$/.test(value) || !/FREQ=/.test(value)) {
    throw new HttpsError("invalid-argument", "Choose a valid repeat.");
  }
  return value;
}

/**
 * When a series stops: the end of its UNTIL day, or six months after it
 * starts when it never ends (the invite then lapses; calendars keep it).
 * @param {string} recurrence RRULE line.
 * @param {number} start First occurrence, epoch ms.
 * @return {number} Epoch ms.
 */
function seriesEnd(recurrence, start) {
  const match = /UNTIL=(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z)?/
      .exec(recurrence);
  if (!match) return start + OPEN_SERIES_MS;
  const [, y, mo, d, h, mi, s] = match.map(Number);
  return match[4] ?
    Date.UTC(y, mo - 1, d, h, mi, s) :
    Date.UTC(y, mo - 1, d) + DAY_MS;
}

/**
 * Validates a new invite.
 * @param {object} data Callable data.
 * @param {string} senderUid Caller.
 * @param {number} now Epoch ms.
 * @return {object} Event fields plus recipientUids and senderEventId.
 */
function validatedInviteInput(data, senderUid, now) {
  const fields = validatedEventFields(data, now);
  if (!Array.isArray(data?.recipientUids)) {
    throw new HttpsError("invalid-argument", "Choose friends to invite.");
  }
  const recipientUids = [...new Set(data.recipientUids
      .filter((value) => typeof value === "string")
      .map((value) => value.trim())
      .filter((value) => value && !value.includes("/") &&
        value !== senderUid))];
  if (recipientUids.length === 0 || recipientUids.length > MAX_RECIPIENTS) {
    throw new HttpsError(
        "invalid-argument",
        `Choose between 1 and ${MAX_RECIPIENTS} friends.`,
    );
  }
  const senderEventId = typeof data?.senderEventId === "string" &&
    data.senderEventId.length <= 1500 ? data.senderEventId : null;
  return {...fields, recipientUids, senderEventId};
}

/**
 * The update recording [uid]'s answer, or null when it is already recorded.
 * @param {object} invite Invite data.
 * @param {string} uid Responder.
 * @param {boolean} accept Going or not.
 * @param {number} now Epoch ms.
 * @return {object|null} Fields to update.
 */
function responseUpdate(invite, uid, accept, now) {
  if (!invite.recipientUids?.includes(uid)) {
    throw new HttpsError(
        "permission-denied",
        "This invite does not belong to you.",
    );
  }
  if (invite.status !== "active") {
    throw new HttpsError("failed-precondition", "This invite was cancelled.");
  }
  // A series stays answerable until its last occurrence (expireAt).
  const last = invite.recurrence ? invite.expireAt : invite.end;
  const end = last?.toMillis?.() ?? last;
  if (end <= now) {
    throw new HttpsError("failed-precondition", "This event has ended.");
  }
  // null undoes a decline straight back to waiting (the decline toast's
  // Undo); it can't clear an acceptance.
  if (accept === null && invite.responses?.[uid] !== "declined") return null;
  const answer = accept === null ? "pending" :
    accept ? "accepted" : "declined";
  if (invite.responses?.[uid] === answer) return null;
  return {[`responses.${uid}`]: answer};
}

/**
 * What the sender is told when someone answers or changes their answer.
 * @param {string} name Responder's username.
 * @param {string} title Event title.
 * @param {string} previous Their answer before this one.
 * @param {boolean} accept Going or not.
 * @return {string} Push body.
 */
function responseMessage(name, title, previous, accept) {
  if (accept) {
    return previous === "declined" ?
      `${name} can attend ${title} after all` :
      `${name} accepted ${title}`;
  }
  return previous === "accepted" ?
    `${name} can no longer make ${title}` :
    `${name} declined ${title}`;
}

/**
 * Takes [uid] out of an invite (unfriended, blocked or deleted). The sender
 * leaving, or the last recipient, cancels it.
 * @param {object} invite Invite data.
 * @param {string} uid Person leaving.
 * @return {object} Fields to update.
 */
function removalUpdate(invite, uid) {
  if (invite.fromUid === uid) return {status: "cancelled"};
  const recipientUids = (invite.recipientUids || [])
      .filter((value) => value !== uid);
  const responses = {...invite.responses};
  const recipientNames = {...invite.recipientNames};
  delete responses[uid];
  delete recipientNames[uid];
  return recipientUids.length ?
    {recipientUids, responses, recipientNames} :
    {recipientUids, responses, recipientNames, status: "cancelled"};
}

async function senderInvite(db, uid, data) {
  const inviteId = stringId(data?.inviteId, "inviteId");
  const reference = db.collection("event_invites").doc(inviteId);
  const snapshot = await reference.get();
  if (!snapshot.exists || snapshot.data().fromUid !== uid) {
    throw new HttpsError("not-found", "Invite not found.");
  }
  return snapshot;
}

/**
 * Who hears about a change or cancellation: everyone still invited who
 * hasn't declined.
 * @param {object} invite Invite data.
 * @return {string[]} uids.
 */
function changeAudience(invite) {
  return (invite.recipientUids || [])
      .filter((uid) => invite.responses?.[uid] !== "declined");
}

/**
 * Whether an edit touches anything friends see.
 * @param {object} invite Invite data (Timestamps or millis).
 * @param {object} fields Validated {title, start, end, allDay}.
 * @return {boolean} True when something changed.
 */
function eventChanged(invite, fields) {
  const millis = (value) => value?.toMillis?.() ?? value;
  return invite.title !== fields.title || invite.allDay !== fields.allDay ||
    millis(invite.start) !== fields.start ||
    millis(invite.end) !== fields.end ||
    (invite.recurrence ?? null) !== (fields.recurrence ?? null);
}

/**
 * The occurrence changes still worth keeping after a series edit. Moving the
 * series moves every occurrence, so the old changes no longer line up;
 * ending it earlier drops only the changes past the new end.
 * @param {object} invite Invite data (Timestamps or millis).
 * @param {object} fields Validated event fields, with until.
 * @return {object} exceptions map.
 */
function keptExceptions(invite, fields) {
  const millis = (value) => value?.toMillis?.() ?? value;
  if (invite.allDay !== fields.allDay ||
      millis(invite.start) !== fields.start ||
      millis(invite.end) !== fields.end) {
    return {};
  }
  return Object.fromEntries(Object.entries(invite.exceptions || {})
      .filter(([original]) => Number(original) < fields.until));
}

/**
 * The update recording a change to one occurrence of a series, keyed by
 * where it originally started (epoch ms), or null when nothing changed.
 * @param {object} invite Invite data (Timestamps or millis).
 * @param {object} data Callable data: originalStart, and cancelled or
 *   title/start/end.
 * @param {number} now Epoch ms.
 * @return {object|null} Fields to update.
 */
function occurrenceUpdate(invite, data, now) {
  const millis = (value) => value?.toMillis?.() ?? value;
  if (invite.status !== "active" || !invite.recurrence) {
    throw new HttpsError(
        "failed-precondition",
        "Only a repeating invite has occurrences.",
    );
  }
  const original = Number(data?.originalStart);
  if (!Number.isInteger(original) || original < millis(invite.start) ||
      original >= millis(invite.expireAt)) {
    throw new HttpsError(
        "invalid-argument",
        "That occurrence isn't part of this event.",
    );
  }
  let change;
  if (data?.cancelled === true) {
    change = {cancelled: true};
  } else {
    const fields = validatedEventFields(
        {title: data?.title, start: data?.start, end: data?.end}, now);
    change = {title: fields.title, start: fields.start, end: fields.end};
  }
  const exceptions = invite.exceptions || {};
  const key = String(original);
  if (JSON.stringify(exceptions[key]) === JSON.stringify(change)) return null;
  if (!(key in exceptions) &&
      Object.keys(exceptions).length >= MAX_EXCEPTIONS) {
    throw new HttpsError(
        "resource-exhausted",
        "Too many single changes to this event.",
    );
  }
  return {[`exceptions.${key}`]: change};
}

async function pushToRecipients(db, invite, title, body, type) {
  const messaging = admin.messaging();
  await Promise.all(changeAudience(invite).map((uid) => pushToUser(
      db.collection("users").doc(uid), messaging,
      "circleNotificationsEnabled", {
        notification: {title, body},
        data: {screen: "invites", type},
      }).catch((error) => console.warn("Invite push failed", error))));
}

exports.sendEventInvites = onCall(async (request) => {
  const uid = requireAuth(request);
  const nowMs = Date.now();
  const input = validatedInviteInput(request.data, uid, nowMs);
  const db = admin.firestore();
  await requireBudget(db, uid, "social");
  // Both sides: the sender's own list alone is theirs to write.
  const friendships = await db.getAll(...input.recipientUids.flatMap(
      (friend) => [
        db.doc(`users/${uid}/circle/relationships/friends/${friend}`),
        db.doc(`users/${friend}/circle/relationships/friends/${uid}`),
      ]));
  if (friendships.some((snapshot) => !snapshot.exists)) {
    throw new HttpsError(
        "permission-denied",
        "Invites can only be sent to current Circle friends.",
    );
  }
  const blocks = await db.getAll(...input.recipientUids.flatMap((friend) => [
    db.doc(`circle_blocks/${uid}/users/${friend}`),
    db.doc(`circle_blocks/${friend}/users/${uid}`),
  ]));
  if (blocks.some((snapshot) => snapshot.exists)) {
    throw new HttpsError("permission-denied", "Cannot invite this user.");
  }
  const [senderProfile, ...recipientProfiles] = await db.getAll(
      ...[uid, ...input.recipientUids].map((person) =>
        db.doc(`users/${person}/circle/profile`)));
  const profile = senderProfile.data();
  const fromName = shortName(profile?.username, "A Circle friend");
  const now = Timestamp.now();
  const reference = db.collection("event_invites").doc();
  await reference.set({
    fromUid: uid,
    fromName,
    fromPhotoUrl: ownPhoto(profile?.photoUrl),
    title: input.title,
    start: Timestamp.fromMillis(input.start),
    end: Timestamp.fromMillis(input.end),
    allDay: input.allDay,
    recurrence: input.recurrence,
    recipientUids: input.recipientUids,
    // So the sender can see who said what.
    recipientNames: Object.fromEntries(input.recipientUids.map((friend, i) =>
      [friend, shortName(recipientProfiles[i].data()?.username, "A friend")])),
    responses: Object.fromEntries(
        input.recipientUids.map((friend) => [friend, "pending"])),
    status: "active",
    senderEventId: input.senderEventId,
    createdAt: now,
    updatedAt: now,
    // Invites expire when the event ends: the app stops showing them and a
    // Firestore TTL policy on expireAt deletes them.
    expireAt: Timestamp.fromMillis(input.until),
  });
  const messaging = admin.messaging();
  await Promise.all(input.recipientUids.map((friend) => pushToUser(
      db.collection("users").doc(friend), messaging,
      "circleNotificationsEnabled", {
        notification: {
          title: "Event invite",
          body: `${fromName} invited you to ${input.title}`,
        },
        data: {screen: "invites", type: "event_invite", inviteId: reference.id},
      }).catch((error) => console.warn("Invite push failed", error))));
  return {inviteId: reference.id};
});

exports.respondToEventInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const inviteId = stringId(request.data?.inviteId, "inviteId");
  const accept = request.data?.accept;
  if (typeof accept !== "boolean" && accept !== null) {
    throw new HttpsError("invalid-argument", "accept is required.");
  }
  const db = admin.firestore();
  await requireBudget(db, uid, "social");
  const reference = db.collection("event_invites").doc(inviteId);
  const invite = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Invite not found.");
    }
    const update = responseUpdate(snapshot.data(), uid, accept, Date.now());
    if (!update) return null;
    transaction.update(reference, {
      ...update, updatedAt: Timestamp.now(),
    });
    return snapshot.data();
  });
  // Undoing a decline is quiet: the sender's list just shows waiting again.
  if (invite && accept !== null) {
    const name = shortName((await db.doc(`users/${uid}/circle/profile`).get())
        .data()?.username, "A friend");
    await pushToUser(db.collection("users").doc(invite.fromUid),
        admin.messaging(), "circleNotificationsEnabled", {
          notification: {
            title: "Event invite",
            body: responseMessage(name, invite.title,
                invite.responses?.[uid], accept),
          },
          data: {screen: "invites", type: "event_invite_response"},
        }).catch((error) => console.warn("Invite push failed", error));
  }
  return {recorded: invite !== null};
});

exports.updateEventInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  await requireBudget(db, uid, "social");
  const snapshot = await senderInvite(db, uid, request.data);
  const fields = validatedEventFields(request.data, Date.now());
  const invite = snapshot.data();
  if (invite.status !== "active" || !eventChanged(invite, fields)) {
    return {updated: false};
  }
  await snapshot.ref.update({
    title: fields.title,
    start: Timestamp.fromMillis(fields.start),
    end: Timestamp.fromMillis(fields.end),
    allDay: fields.allDay,
    recurrence: fields.recurrence,
    exceptions: keptExceptions(invite, fields),
    expireAt: Timestamp.fromMillis(fields.until),
    updatedAt: Timestamp.now(),
  });
  await pushToRecipients(db, invite, "Event updated",
      `${invite.fromName} changed ${fields.title}. Open Vivordo to see ` +
      "the new details.", "event_invite_changed");
  return {updated: true};
});

exports.updateEventInviteOccurrence = onCall(async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  await requireBudget(db, uid, "social");
  const snapshot = await senderInvite(db, uid, request.data);
  const invite = snapshot.data();
  const update = occurrenceUpdate(invite, request.data, Date.now());
  if (!update) return {updated: false};
  await snapshot.ref.update({
    ...update, updatedAt: Timestamp.now(),
  });
  // No date: the server doesn't know each friend's time zone. The
  // Invites screen shows which one.
  await pushToRecipients(db, invite, "Event updated",
      request.data?.cancelled === true ?
        `${invite.fromName} cancelled one ${invite.title}.` :
        `${invite.fromName} changed one ${invite.title}. Open Vivordo to ` +
        "see which.", "event_invite_changed");
  return {updated: true};
});

exports.cancelEventInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  await requireBudget(db, uid, "social");
  const snapshot = await senderInvite(db, uid, request.data);
  if (snapshot.data().status === "cancelled") return {cancelled: true};
  await snapshot.ref.update({
    status: "cancelled",
    updatedAt: Timestamp.now(),
  });
  const invite = snapshot.data();
  await pushToRecipients(db, invite, "Event cancelled",
      `${invite.fromName} cancelled ${invite.title}.`,
      "event_invite_cancelled");
  return {cancelled: true};
});

/**
 * Takes [uid] and [other] out of each other's invites (unfriend or block).
 * @param {string} uid One person.
 * @param {string} other The other.
 */
async function removeEventInvitesBetween(uid, other) {
  const db = admin.firestore();
  const invites = db.collection("event_invites");
  const [sent, received] = await Promise.all([
    invites.where("fromUid", "==", uid)
        .where("recipientUids", "array-contains", other).get(),
    invites.where("fromUid", "==", other)
        .where("recipientUids", "array-contains", uid).get(),
  ]);
  const writer = db.bulkWriter();
  for (const document of sent.docs) {
    writer.update(document.ref, removalUpdate(document.data(), other));
  }
  for (const document of received.docs) {
    writer.update(document.ref, removalUpdate(document.data(), uid));
  }
  await writer.close();
}

/**
 * Deletes [uid]'s invites and takes them out of everyone else's.
 * @param {string} uid Deleted account.
 */
async function deleteUserEventInvites(uid) {
  const db = admin.firestore();
  const invites = db.collection("event_invites");
  const [sent, received] = await Promise.all([
    invites.where("fromUid", "==", uid).get(),
    invites.where("recipientUids", "array-contains", uid).get(),
  ]);
  const writer = db.bulkWriter();
  for (const document of sent.docs) writer.delete(document.ref);
  for (const document of received.docs) {
    if (document.data().fromUid === uid) continue;
    writer.update(document.ref, removalUpdate(document.data(), uid));
  }
  await writer.close();
}

exports.removeEventInvitesBetween = removeEventInvitesBetween;
exports.deleteUserEventInvites = deleteUserEventInvites;
exports.validatedInviteInput = validatedInviteInput;
exports.responseUpdate = responseUpdate;
exports.removalUpdate = removalUpdate;
exports.responseMessage = responseMessage;
exports.changeAudience = changeAudience;
exports.eventChanged = eventChanged;
exports.seriesEnd = seriesEnd;
exports.keptExceptions = keptExceptions;
exports.occurrenceUpdate = occurrenceUpdate;
