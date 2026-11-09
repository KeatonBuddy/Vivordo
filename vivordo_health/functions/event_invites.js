"use strict";
/* eslint-disable require-jsdoc */
// Calendar invites between Circle friends. Clients only read
// event_invites/{id}; every write comes through these callables, which
// check friendships and blocks the way createChallenge does.
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {pushToUser} = require("./push");

const MAX_RECIPIENTS = 20;
const MAX_TITLE_LENGTH = 200;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_LENGTH_MS = 7 * DAY_MS;
const MAX_AHEAD_MS = 366 * DAY_MS;

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
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
      end - start > MAX_LENGTH_MS || end < now ||
      start > now + MAX_AHEAD_MS) {
    throw new HttpsError("invalid-argument", "Choose a valid event time.");
  }
  return {title, start, end, allDay: data?.allDay === true};
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
 * @return {object|null} Fields to update.
 */
function responseUpdate(invite, uid, accept) {
  if (!invite.recipientUids?.includes(uid)) {
    throw new HttpsError(
        "permission-denied",
        "This invite does not belong to you.",
    );
  }
  if (invite.status !== "active") {
    throw new HttpsError("failed-precondition", "This invite was cancelled.");
  }
  const answer = accept ? "accepted" : "declined";
  if (invite.responses?.[uid] === answer) return null;
  return {[`responses.${uid}`]: answer};
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
  delete responses[uid];
  return recipientUids.length ?
    {recipientUids, responses} :
    {recipientUids, responses, status: "cancelled"};
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

// Pushes to everyone on [invite] who said yes.
async function pushToAccepted(db, invite, body) {
  const messaging = admin.messaging();
  await Promise.all(Object.entries(invite.responses || {})
      .filter(([, answer]) => answer === "accepted")
      .map(([uid]) => pushToUser(db.collection("users").doc(uid), messaging,
          "circleNotificationsEnabled", {
            notification: {title: invite.title, body},
            data: {screen: "invites", type: "event_invite_changed"},
          })));
}

exports.sendEventInvites = onCall(async (request) => {
  const uid = requireAuth(request);
  const nowMs = Date.now();
  const input = validatedInviteInput(request.data, uid, nowMs);
  const db = admin.firestore();
  const friendships = await db.getAll(...input.recipientUids.map((friend) =>
    db.doc(`users/${uid}/circle/relationships/friends/${friend}`)));
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
  const profile = (await db.doc(`users/${uid}/circle/profile`).get()).data();
  const fromName = profile?.username || "A Circle friend";
  const now = admin.firestore.Timestamp.now();
  const reference = db.collection("event_invites").doc();
  await reference.set({
    fromUid: uid,
    fromName,
    fromPhotoUrl: profile?.photoUrl || null,
    title: input.title,
    start: admin.firestore.Timestamp.fromMillis(input.start),
    end: admin.firestore.Timestamp.fromMillis(input.end),
    allDay: input.allDay,
    recipientUids: input.recipientUids,
    responses: Object.fromEntries(
        input.recipientUids.map((friend) => [friend, "pending"])),
    status: "active",
    senderEventId: input.senderEventId,
    createdAt: now,
    updatedAt: now,
    // A Firestore TTL policy on expireAt deletes answered and past invites.
    expireAt: admin.firestore.Timestamp.fromMillis(input.end + DAY_MS),
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
  if (typeof accept !== "boolean") {
    throw new HttpsError("invalid-argument", "accept is required.");
  }
  const db = admin.firestore();
  const reference = db.collection("event_invites").doc(inviteId);
  const invite = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Invite not found.");
    }
    const update = responseUpdate(snapshot.data(), uid, accept);
    if (!update) return null;
    transaction.update(reference, {
      ...update, updatedAt: admin.firestore.Timestamp.now(),
    });
    return snapshot.data();
  });
  if (invite && accept) {
    const name = (await db.doc(`users/${uid}/circle/profile`).get())
        .data()?.username || "A friend";
    await pushToUser(db.collection("users").doc(invite.fromUid),
        admin.messaging(), "circleNotificationsEnabled", {
          notification: {title: invite.title, body: `${name} is going`},
          data: {screen: "invites", type: "event_invite_accepted"},
        }).catch((error) => console.warn("Invite push failed", error));
  }
  return {recorded: invite !== null};
});

exports.updateEventInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const snapshot = await senderInvite(db, uid, request.data);
  const fields = validatedEventFields(request.data, Date.now());
  await snapshot.ref.update({
    title: fields.title,
    start: admin.firestore.Timestamp.fromMillis(fields.start),
    end: admin.firestore.Timestamp.fromMillis(fields.end),
    allDay: fields.allDay,
    expireAt: admin.firestore.Timestamp.fromMillis(fields.end + DAY_MS),
    updatedAt: admin.firestore.Timestamp.now(),
  });
  await pushToAccepted(db, {...snapshot.data(), title: fields.title},
      "The time or details changed.").catch((error) =>
    console.warn("Invite push failed", error));
  return {updated: true};
});

exports.cancelEventInvite = onCall(async (request) => {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const snapshot = await senderInvite(db, uid, request.data);
  if (snapshot.data().status === "cancelled") return {cancelled: true};
  await snapshot.ref.update({
    status: "cancelled",
    updatedAt: admin.firestore.Timestamp.now(),
  });
  await pushToAccepted(db, snapshot.data(), "This event was cancelled.")
      .catch((error) => console.warn("Invite push failed", error));
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
