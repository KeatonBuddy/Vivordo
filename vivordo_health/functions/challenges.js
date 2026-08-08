/* eslint-disable require-jsdoc */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const CHALLENGE_TYPES = Object.freeze({
  workout_count: {
    title: "Workout Streak",
    unit: "workouts",
    minimum: 1,
    maximum: 100,
    allowsTarget: true,
  },
  activity_count: {
    title: "Activity Challenge",
    unit: "sessions",
    minimum: 1,
    maximum: 100,
    allowsTarget: true,
  },
  journal_count: {
    title: "Journal Streak",
    unit: "days",
    minimum: 1,
    maximum: 100,
  },
  step_total: {
    title: "Step Sprint",
    unit: "steps",
    minimum: 5000,
    maximum: 1000000,
  },
  scan_count: {
    title: "Pulse Check",
    unit: "scans",
    minimum: 1,
    maximum: 100,
  },
});
const MAX_INVITEES = 7;
const MAX_DURATION_DAYS = 30;
const MAX_TARGET_NAME_LENGTH = 80;
const MAX_MESSAGE_LENGTH = 200;
const INVITE_EXPIRY_HOURS = 48;
const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }
  return request.auth.uid;
}

function membershipReference(db, uid, challengeId) {
  return db.collection("challenge_memberships").doc(uid)
      .collection("items").doc(challengeId);
}

function profileReference(db, uid) {
  return db.collection("users").doc(uid).collection("circle").doc("profile");
}

function challengeMedalReference(db, uid, challengeId) {
  return db.collection("challenge_medal_awards").doc(uid)
      .collection("items").doc(challengeId);
}

function friendReference(db, ownerUid, friendUid) {
  return db.collection("users").doc(ownerUid).collection("circle")
      .doc("relationships").collection("friends").doc(friendUid);
}

function uniqueInvitees(rawInvitees, creatorUid) {
  if (!Array.isArray(rawInvitees)) {
    throw new HttpsError(
        "invalid-argument",
        "participantUids must be a list of Circle friends.",
    );
  }
  const invitees = [...new Set(rawInvitees
      .filter((value) => typeof value === "string")
      .map((value) => value.trim())
      .filter((value) => value && value !== creatorUid))];
  if (invitees.length === 0 || invitees.length > MAX_INVITEES) {
    throw new HttpsError(
        "invalid-argument",
        `Choose between 1 and ${MAX_INVITEES} friends.`,
    );
  }
  return invitees;
}

function validatedChallengeInput(request, creatorUid) {
  const type = request.data?.type;
  const definition = CHALLENGE_TYPES[type];
  if (!definition) {
    throw new HttpsError("invalid-argument", "Unsupported challenge type.");
  }
  const goal = Number(request.data?.goal);
  if (!Number.isInteger(goal) ||
      goal < definition.minimum || goal > definition.maximum) {
    throw new HttpsError(
        "invalid-argument",
        `Goal must be between ${definition.minimum} and ` +
        `${definition.maximum} ${definition.unit}.`,
    );
  }
  const durationDays = Number(request.data?.durationDays);
  if (!Number.isInteger(durationDays) ||
      durationDays < 1 || durationDays > MAX_DURATION_DAYS) {
    throw new HttpsError(
        "invalid-argument",
        `Duration must be between 1 and ${MAX_DURATION_DAYS} days.`,
    );
  }
  const rawTargetName = request.data?.targetName;
  const targetName = typeof rawTargetName === "string" ?
    rawTargetName.trim() : "";
  if (targetName.length > MAX_TARGET_NAME_LENGTH ||
      (targetName && !definition.allowsTarget)) {
    throw new HttpsError(
        "invalid-argument",
        "The selected workout or activity is not valid.",
    );
  }
  const rawMessage = request.data?.message;
  if (rawMessage != null && typeof rawMessage !== "string") {
    throw new HttpsError("invalid-argument", "Message must be text.");
  }
  const message = typeof rawMessage === "string" ? rawMessage.trim() : "";
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError(
        "invalid-argument",
        `Message must be ${MAX_MESSAGE_LENGTH} characters or fewer.`,
    );
  }
  return {
    type,
    definition,
    title: targetName || definition.title,
    targetName: targetName || null,
    message: message || null,
    goal,
    durationDays,
    invitees: uniqueInvitees(request.data?.participantUids, creatorUid),
  };
}

function timestampAfter(timestamp, duration) {
  return admin.firestore.Timestamp.fromMillis(
      timestamp.toMillis() + duration,
  );
}

function utcDayKey(timestamp) {
  const date = timestamp.toDate();
  return [
    date.getUTCFullYear().toString().padStart(4, "0"),
    (date.getUTCMonth() + 1).toString().padStart(2, "0"),
    date.getUTCDate().toString().padStart(2, "0"),
  ].join("-");
}

function membershipData({
  challengeId,
  creatorUid,
  creatorName,
  type,
  definition,
  title,
  targetName,
  message,
  goal,
  durationDays,
  participantUids,
  role,
  status,
  now,
}) {
  return {
    challengeId,
    creatorUid,
    creatorName,
    type,
    title,
    targetName,
    message,
    goal,
    unit: definition.unit,
    durationDays,
    scoringMode: "individual_goal",
    participantUids,
    participantCount: participantUids.length,
    role,
    status,
    progress: 0,
    totalProgress: 0,
    createdAt: now,
    updatedAt: now,
  };
}

exports.createChallenge = onCall(async (request) => {
  const creatorUid = requireAuth(request);
  const input = validatedChallengeInput(request, creatorUid);
  const db = admin.firestore();
  const friendshipSnapshots = await db.getAll(
      ...input.invitees.map((uid) => friendReference(db, creatorUid, uid)),
  );
  if (friendshipSnapshots.some((snapshot) => !snapshot.exists)) {
    throw new HttpsError(
        "permission-denied",
        "Challenges can only be sent to current Circle friends.",
    );
  }

  const profileUids = [creatorUid, ...input.invitees];
  const profileSnapshots = await db.getAll(
      ...profileUids.map((uid) => profileReference(db, uid)),
  );
  const creatorName = profileSnapshots[0].data()?.username || "A friend";
  const participantNames = {};
  profileUids.forEach((uid, index) => {
    participantNames[uid] = profileSnapshots[index].data()?.username ||
      "Circle member";
  });

  const challengeReference = db.collection("challenges").doc();
  const challengeId = challengeReference.id;
  const participantUids = [creatorUid, ...input.invitees];
  const now = admin.firestore.Timestamp.now();
  const pendingExpiresAt = timestampAfter(
      now,
      INVITE_EXPIRY_HOURS * 60 * 60 * 1000,
  );
  const batch = db.batch();
  batch.set(challengeReference, {
    schemaVersion: 2,
    creatorUid,
    creatorName,
    type: input.type,
    title: input.title,
    targetName: input.targetName,
    message: input.message,
    goal: input.goal,
    unit: input.definition.unit,
    durationDays: input.durationDays,
    scoringMode: "individual_goal",
    participantUids,
    participantNames,
    acceptedUids: [creatorUid],
    pendingUids: input.invitees,
    declinedUids: [],
    activeParticipantUids: [],
    completedUids: [],
    status: "pending",
    totalProgress: 0,
    createdAt: now,
    updatedAt: now,
    pendingExpiresAt,
  });

  for (const uid of participantUids) {
    const isCreator = uid === creatorUid;
    batch.set(challengeReference.collection("participants").doc(uid), {
      uid,
      username: participantNames[uid],
      role: isCreator ? "creator" : "participant",
      status: isCreator ? "accepted" : "pending",
      progress: 0,
      invitedAt: now,
      acceptedAt: isCreator ? now : null,
      updatedAt: now,
    });
    batch.set(
        membershipReference(db, uid, challengeId),
        membershipData({
          challengeId,
          creatorUid,
          creatorName,
          type: input.type,
          definition: input.definition,
          title: input.title,
          targetName: input.targetName,
          message: input.message,
          goal: input.goal,
          durationDays: input.durationDays,
          participantUids,
          role: isCreator ? "creator" : "participant",
          status: isCreator ? "waiting" : "pending",
          now,
        }),
    );
  }
  await batch.commit();
  return {challengeId};
});

exports.respondToChallenge = onCall(async (request) => {
  const uid = requireAuth(request);
  const challengeId = typeof request.data?.challengeId === "string" ?
    request.data.challengeId.trim() : "";
  const accept = request.data?.accept;
  if (!challengeId || typeof accept !== "boolean") {
    throw new HttpsError(
        "invalid-argument",
        "challengeId and accept are required.",
    );
  }
  const db = admin.firestore();
  const challengeReference = db.collection("challenges").doc(challengeId);
  const response = await db.runTransaction(async (transaction) => {
    const challengeSnapshot = await transaction.get(challengeReference);
    if (!challengeSnapshot.exists) {
      throw new HttpsError("not-found", "Challenge not found.");
    }
    const challenge = challengeSnapshot.data();
    if (!challenge.participantUids?.includes(uid) ||
        challenge.creatorUid === uid) {
      throw new HttpsError(
          "permission-denied",
          "This invitation does not belong to you.",
      );
    }
    const participantReference = challengeReference
        .collection("participants").doc(uid);
    const participantSnapshot = await transaction.get(participantReference);
    const participantStatus = participantSnapshot.data()?.status;
    const desiredStatus = accept ? "accepted" : "declined";
    if (participantStatus === desiredStatus ||
        ["active", "completed"].includes(challenge.status)) {
      return {
        alreadyProcessed: true,
        activated: challenge.status === "active",
        creatorUid: challenge.creatorUid,
        acceptedUids: challenge.acceptedUids || [],
        title: challenge.title,
      };
    }
    if (challenge.status !== "pending" || participantStatus !== "pending") {
      throw new HttpsError(
          "failed-precondition",
          "This invitation can no longer be changed.",
      );
    }

    const pendingUids = (challenge.pendingUids || [])
        .filter((participantUid) => participantUid !== uid);
    const acceptedUids = [...(challenge.acceptedUids || [])];
    const declinedUids = [...(challenge.declinedUids || [])];
    if (accept && !acceptedUids.includes(uid)) acceptedUids.push(uid);
    if (!accept && !declinedUids.includes(uid)) declinedUids.push(uid);
    const now = admin.firestore.Timestamp.now();
    const activated = pendingUids.length === 0 && acceptedUids.length >= 2;
    const cancelled = pendingUids.length === 0 && acceptedUids.length < 2;
    const status = activated ? "active" : cancelled ? "cancelled" : "pending";
    const startAt = activated ? now : null;
    const endAt = activated ? timestampAfter(
        now,
        Number(challenge.durationDays) * 24 * 60 * 60 * 1000,
    ) : null;
    const startDay = startAt ? utcDayKey(startAt) : null;
    const endDay = endAt ? utcDayKey(endAt) : null;
    const stepBaselines = {};
    if (activated && challenge.type === "step_total" && startDay) {
      // A daily steps document includes steps taken before the challenge began.
      // Capture each participant's current total inside the activation
      // transaction so only subsequent steps contribute to the challenge.
      for (const participantUid of acceptedUids) {
        const dailyReference = db.collection("users").doc(participantUid)
            .collection("metrics_daily").doc(startDay);
        const dailySnapshot = await transaction.get(dailyReference);
        stepBaselines[participantUid] = stepTotal(dailySnapshot.data());
      }
    }

    transaction.update(challengeReference, {
      pendingUids,
      acceptedUids,
      declinedUids,
      activeParticipantUids: activated ? acceptedUids : [],
      status,
      startAt,
      endAt,
      startDay,
      endDay,
      updatedAt: now,
    });
    transaction.set(participantReference, {
      status: desiredStatus,
      acceptedAt: accept ? now : null,
      declinedAt: accept ? null : now,
      updatedAt: now,
    }, {merge: true});

    for (const [participantUid, baseline] of
      Object.entries(stepBaselines)) {
      transaction.set(
          challengeReference.collection("contributions")
              .doc(`${participantUid}__steps__${startDay}`),
          {
            uid: participantUid,
            sourceType: "steps_day",
            sourceId: startDay,
            baseline,
            value: 0,
            occurredAt: startAt,
            updatedAt: now,
          },
      );
    }

    for (const participantUid of challenge.participantUids || []) {
      let membershipStatus = "pending";
      if (declinedUids.includes(participantUid)) {
        membershipStatus = "declined";
      } else if (activated && acceptedUids.includes(participantUid)) {
        membershipStatus = "active";
      } else if (cancelled) {
        membershipStatus = "cancelled";
      } else if (acceptedUids.includes(participantUid)) {
        membershipStatus = "waiting";
      }
      if (activated && acceptedUids.includes(participantUid)) {
        transaction.set(
            challengeReference.collection("participants").doc(participantUid),
            {status: "active", updatedAt: now},
            {merge: true},
        );
      }
      transaction.set(
          membershipReference(db, participantUid, challengeId),
          {
            status: membershipStatus,
            startAt,
            endAt,
            startDay,
            endDay,
            activeParticipantUids: activated ? acceptedUids : [],
            updatedAt: now,
          },
          {merge: true},
      );
    }
    return {
      alreadyProcessed: false,
      activated,
      creatorUid: challenge.creatorUid,
      acceptedUids,
      title: challenge.title,
      accepted: accept,
    };
  });

  if (!response.alreadyProcessed) {
    const responder = await profileReference(db, uid).get();
    const responderName = responder.data()?.username || "A Circle friend";
    await sendChallengeNotification(
        response.creatorUid,
        "Circle",
        `${responderName} ${accept ? "accepted" : "declined"} your ` +
          `${response.title} challenge`,
        {type: "challenge_response", challengeId},
    );
    if (response.activated) {
      await Promise.all(response.acceptedUids.map((participantUid) =>
        sendChallengeNotification(
            participantUid,
            "Circle",
            `${response.title} has started`,
            {type: "challenge_started", challengeId},
        ),
      ));
    }
  }
  return {status: response.activated ? "active" : "pending"};
});

exports.cancelChallenge = onCall(async (request) => {
  const uid = requireAuth(request);
  const challengeId = typeof request.data?.challengeId === "string" ?
    request.data.challengeId.trim() : "";
  if (!challengeId) {
    throw new HttpsError("invalid-argument", "challengeId is required.");
  }
  const db = admin.firestore();
  const challengeReference = db.collection("challenges").doc(challengeId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(challengeReference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Challenge not found.");
    }
    const challenge = snapshot.data();
    if (challenge.creatorUid !== uid) {
      throw new HttpsError(
          "permission-denied",
          "Only the challenge creator can cancel it.",
      );
    }
    if (!["pending", "active"].includes(challenge.status)) return;
    const now = admin.firestore.Timestamp.now();
    transaction.update(challengeReference, {
      status: "cancelled",
      cancelledAt: now,
      updatedAt: now,
    });
    for (const participantUid of challenge.participantUids || []) {
      transaction.set(
          membershipReference(db, participantUid, challengeId),
          {status: "cancelled", updatedAt: now},
          {merge: true},
      );
    }
  });
  return {status: "cancelled"};
});

exports.challengeInviteNotification = onDocumentCreated(
    "challenge_memberships/{uid}/items/{challengeId}",
    async (event) => {
      const membership = event.data?.data();
      if (!membership || membership.status !== "pending") return;
      await sendChallengeNotification(
          event.params.uid,
          "Challenge invite",
          `${membership.creatorName || "A Circle friend"} ` +
            "sent you a challenge!",
          {
            type: "challenge_invite",
            challengeId: event.params.challengeId,
          },
      );
    },
);

exports.challengeWorkoutProgress = onDocumentWritten(
    "users/{uid}/workouts/{workoutId}",
    async (event) => {
      const uid = event.params.uid;
      const workoutId = event.params.workoutId;
      const workout = event.data?.after.exists ? event.data.after.data() : null;
      const memberships = await activeMemberships(uid);
      if (memberships.empty) return;
      const occurredAt = workout?.completedAt || workout?.startedAt || null;
      await Promise.all(memberships.docs
          .filter((membership) =>
            ["workout_count", "activity_count"].includes(
                membership.data().type,
            ),
          )
          .map((membership) => {
            const data = membership.data();
            const withinWindow = workout && timestampWithin(
                occurredAt,
                data.startAt,
                data.endAt,
            );
            const matches = withinWindow &&
              workoutMatchesChallenge(workout, data);
            return applyContribution({
              challengeId: membership.id,
              uid,
              sourceKey: `${uid}__workout__${workoutId}`,
              sourceType: data.type === "activity_count" ?
                "activity" : "workout",
              sourceId: workoutId,
              occurredAt,
              value: matches ? 1 : 0,
            });
          }));
    },
);

exports.challengeJournalProgress = onDocumentWritten(
    "users/{uid}/journal_entries/{entryId}",
    async (event) => {
      const uid = event.params.uid;
      const before = event.data?.before.exists ?
        event.data.before.data() : null;
      const after = event.data?.after.exists ? event.data.after.data() : null;
      const dayKeys = new Set([
        journalDayKey(before),
        journalDayKey(after),
      ].filter(Boolean));
      if (dayKeys.size === 0) return;
      const memberships = await activeMemberships(uid, "journal_count");
      if (memberships.empty) return;
      const dailyValues = {};
      await Promise.all([...dayKeys].map(async (dayKey) => {
        dailyValues[dayKey] = await journalEntryExistsForDay(uid, dayKey);
      }));
      await Promise.all(memberships.docs.flatMap((membership) => {
        const data = membership.data();
        return [...dayKeys].map((dayKey) => {
          const dayIsActive = typeof data.startDay === "string" &&
            typeof data.endDay === "string" &&
            dayKey >= data.startDay && dayKey <= data.endDay;
          return applyContribution({
            challengeId: membership.id,
            uid,
            sourceKey: `${uid}__journal_day__${dayKey}`,
            sourceType: "journal_day",
            sourceId: dayKey,
            occurredAt: null,
            value: dayIsActive && dailyValues[dayKey] ? 1 : 0,
          });
        });
      }));
    },
);

exports.challengeMetricProgress = onDocumentWritten(
    "users/{uid}/metrics_daily/{dayId}",
    async (event) => {
      const uid = event.params.uid;
      const dayId = event.params.dayId;
      const metrics = event.data?.after.exists ? event.data.after.data() : null;
      const memberships = await activeMemberships(uid);
      if (memberships.empty) return;
      await Promise.all(memberships.docs
          .filter((membership) =>
            ["step_total", "scan_count"].includes(membership.data().type),
          )
          .map((membership) => {
            const data = membership.data();
            if (data.type === "step_total") {
              const dayIsActive = typeof data.startDay === "string" &&
                typeof data.endDay === "string" &&
                dayId >= data.startDay && dayId <= data.endDay;
              return applyContribution({
                challengeId: membership.id,
                uid,
                sourceKey: `${uid}__steps__${dayId}`,
                sourceType: "steps_day",
                sourceId: dayId,
                occurredAt: null,
                value: dayIsActive ? stepTotal(metrics) : 0,
                subtractBaseline: dayId === data.startDay,
              });
            }
            return applyContribution({
              challengeId: membership.id,
              uid,
              sourceKey: `${uid}__scans__${dayId}`,
              sourceType: "scans_day",
              sourceId: dayId,
              occurredAt: null,
              value: scanCount(metrics, data.startAt, data.endAt),
            });
          }));
    },
);

exports.finalizeChallenges = onSchedule("every 15 minutes", async () => {
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const [active, pending] = await Promise.all([
    db.collection("challenges")
        .where("status", "==", "active")
        .where("endAt", "<=", now)
        .get(),
    db.collection("challenges")
        .where("status", "==", "pending")
        .where("pendingExpiresAt", "<=", now)
        .get(),
  ]);
  await Promise.all([
    ...active.docs.map((document) => expireChallenge(document.ref, "expired")),
    ...pending.docs.map((document) => expireChallenge(document.ref, "expired")),
  ]);
});

async function activeMemberships(uid, type = null) {
  const snapshot = await admin.firestore()
      .collection("challenge_memberships").doc(uid)
      .collection("items").where("status", "==", "active").get();
  if (!type) return snapshot;
  const matching = snapshot.docs.filter((document) =>
    document.data().type === type,
  );
  return {docs: matching, empty: matching.length === 0};
}

function normalizedName(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function workoutMatchesChallenge(workout, challenge) {
  if (!workout) return false;
  const exercises = Array.isArray(workout.exercises) ? workout.exercises : [];
  const targetName = normalizedName(challenge.targetName);
  if (targetName) {
    return normalizedName(workout.activityName) === targetName ||
      exercises.some((exercise) =>
        normalizedName(exercise?.name) === targetName,
      );
  }
  if (challenge.type === "workout_count") return true;
  const category = normalizedName(workout.activityCategory);
  return ["cardio", "sports"].includes(category) ||
    exercises.some((exercise) =>
      ["cardio", "sports"].includes(normalizedName(exercise?.category)),
    );
}

function journalDayKey(entry) {
  const timestamp = entry?.entryDate || entry?.createdAt;
  return timestamp?.toDate ? utcDayKey(timestamp) : null;
}

async function journalEntryExistsForDay(uid, dayKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dayKey);
  if (!match) return false;
  const startMillis = Date.UTC(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
  );
  const start = admin.firestore.Timestamp.fromMillis(startMillis);
  const end = admin.firestore.Timestamp.fromMillis(
      startMillis + 24 * 60 * 60 * 1000,
  );
  const snapshot = await admin.firestore().collection("users").doc(uid)
      .collection("journal_entries")
      .where("entryDate", ">=", start)
      .where("entryDate", "<", end)
      .limit(1)
      .get();
  return !snapshot.empty;
}

function timestampWithin(value, start, end) {
  if (!value?.toMillis || !start?.toMillis || !end?.toMillis) return false;
  const millis = value.toMillis();
  return millis >= start.toMillis() && millis <= end.toMillis();
}

function stepTotal(metrics) {
  const steps = metrics?.steps;
  if (typeof steps === "number" && Number.isFinite(steps)) {
    return Math.max(0, Math.round(steps));
  }
  const candidate = steps?.sum ?? steps?.avg;
  return typeof candidate === "number" && Number.isFinite(candidate) ?
    Math.max(0, Math.round(candidate)) : 0;
}

function scanCount(metrics, startAt, endAt) {
  const scan = metrics?.heart_rate_scan;
  if (!scan || !startAt?.toMillis || !endAt?.toMillis) return 0;
  const start = startAt.toMillis();
  const end = endAt.toMillis();
  if (Array.isArray(scan.entries)) {
    return scan.entries.filter((entry) => {
      const timestamp = entry?.timestamp;
      return timestamp?.toMillis &&
        timestamp.toMillis() >= start && timestamp.toMillis() <= end;
    }).length;
  }
  return timestampWithin(scan.syncedAt, startAt, endAt) &&
    Number.isFinite(scan.avg) ? 1 : 0;
}

async function applyContribution({
  challengeId,
  uid,
  sourceKey,
  sourceType,
  sourceId,
  occurredAt,
  value,
  subtractBaseline = false,
}) {
  const db = admin.firestore();
  const challengeReference = db.collection("challenges").doc(challengeId);
  const participantReference = challengeReference
      .collection("participants").doc(uid);
  const contributionReference = challengeReference
      .collection("contributions").doc(sourceKey);
  const medalReference = challengeMedalReference(db, uid, challengeId);
  const completion = await db.runTransaction(async (transaction) => {
    const challengeSnapshot = await transaction.get(challengeReference);
    const participantSnapshot = await transaction.get(participantReference);
    const contributionSnapshot = await transaction.get(contributionReference);
    if (!challengeSnapshot.exists || !participantSnapshot.exists) return null;
    const challenge = challengeSnapshot.data();
    if (challenge.status !== "active" ||
        !challenge.activeParticipantUids?.includes(uid)) return null;
    const medalSnapshot = await transaction.get(medalReference);
    const previousValue = Number(contributionSnapshot.data()?.value || 0);
    const baseline = subtractBaseline ?
      Number(contributionSnapshot.data()?.baseline || 0) : 0;
    const nextValue = Math.max(
        0,
        Math.round(Number(value) || 0) - baseline,
    );
    const delta = nextValue - previousValue;
    if (delta === 0) return null;
    const participantProgress = Math.max(
        0,
        Number(participantSnapshot.data()?.progress || 0) + delta,
    );
    const totalProgress = Math.max(
        0,
        Number(challenge.totalProgress || 0) + delta,
    );
    const now = admin.firestore.Timestamp.now();
    const participantData = participantSnapshot.data();
    const existingCompletedUids = Array.isArray(challenge.completedUids) ?
      challenge.completedUids : [];
    const wasCompleted = existingCompletedUids.includes(uid) ||
      participantData?.status === "completed";
    const participantCompleted = participantProgress >=
      Number(challenge.goal);
    const shouldAwardMedal = participantCompleted && !wasCompleted &&
      !medalSnapshot.exists;
    const completedUids = participantCompleted && !wasCompleted ?
      [...existingCompletedUids, uid] : existingCompletedUids;
    const activeParticipantUids = challenge.activeParticipantUids || [];
    const allCompleted = activeParticipantUids.length > 0 &&
      activeParticipantUids.every((participantUid) =>
        completedUids.includes(participantUid),
      );

    transaction.set(participantReference, {
      progress: participantProgress,
      status: participantCompleted ? "completed" : "active",
      completedAt: participantCompleted ? now : null,
      updatedAt: now,
    }, {merge: true});
    if (nextValue === 0) {
      if (contributionSnapshot.exists) {
        transaction.delete(contributionReference);
      }
    } else {
      transaction.set(contributionReference, {
        uid,
        sourceType,
        sourceId,
        occurredAt,
        ...(subtractBaseline ? {baseline} : {}),
        value: nextValue,
        updatedAt: now,
      }, {merge: true});
    }
    transaction.update(challengeReference, {
      totalProgress,
      completedUids,
      status: allCompleted ? "completed" : "active",
      completedAt: allCompleted ? now : null,
      updatedAt: now,
    });
    for (const participantUid of activeParticipantUids) {
      const membershipCompleted = completedUids.includes(participantUid);
      const membershipUpdate = {
        totalProgress,
        status: membershipCompleted ? "completed" : "active",
        updatedAt: now,
      };
      if (participantUid === uid) {
        membershipUpdate.progress = participantProgress;
        membershipUpdate.completedAt = participantCompleted ? now : null;
      } else if (!membershipCompleted) {
        membershipUpdate.completedAt = null;
      }
      transaction.set(
          membershipReference(db, participantUid, challengeId),
          membershipUpdate,
          {merge: true},
      );
    }
    if (shouldAwardMedal) {
      transaction.set(medalReference, {
        schemaVersion: 1,
        challengeId,
        uid,
        title: challenge.title,
        type: challenge.type,
        goal: challenge.goal,
        awardedAt: now,
      });
      transaction.set(profileReference(db, uid), {
        challengeMedalCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, {merge: true});
    }
    return participantCompleted && !wasCompleted ? {
      title: challenge.title,
      uid,
    } : null;
  });
  if (completion) {
    await sendChallengeNotification(
        completion.uid,
        "Circle",
        `You completed ${completion.title}`,
        {type: "challenge_completed", challengeId},
    );
  }
}

async function expireChallenge(reference, status) {
  const db = admin.firestore();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists ||
        !["pending", "active"].includes(snapshot.data().status)) return;
    const challenge = snapshot.data();
    const now = admin.firestore.Timestamp.now();
    transaction.update(reference, {
      status,
      expiredAt: now,
      updatedAt: now,
    });
    const completedUids = challenge.completedUids || [];
    for (const uid of challenge.participantUids || []) {
      transaction.set(
          membershipReference(db, uid, reference.id),
          {
            status: completedUids.includes(uid) ? "completed" : status,
            updatedAt: now,
          },
          {merge: true},
      );
    }
  });
}

async function sendChallengeNotification(uid, title, body, data) {
  const db = admin.firestore();
  const userReference = db.collection("users").doc(uid);
  const [user, tokens] = await Promise.all([
    userReference.get(),
    userReference.collection("notification_tokens").get(),
  ]);
  if (user.data()?.preferences?.circleNotificationsEnabled === false ||
      tokens.empty) return;
  const tokenDocuments = tokens.docs.filter((document) =>
    typeof document.data().token === "string" && document.data().token,
  );
  if (tokenDocuments.length === 0) return;
  for (let index = 0; index < tokenDocuments.length; index += 500) {
    const chunk = tokenDocuments.slice(index, index + 500);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk.map((document) => document.data().token),
      notification: {title, body},
      data: {screen: "circle", route: "challenges", ...data},
      apns: {
        headers: {"apns-priority": "10"},
        payload: {aps: {sound: "default"}},
      },
      android: {notification: {sound: "default"}},
    });
    const staleDeletes = [];
    response.responses.forEach((result, resultIndex) => {
      if (!result.success && INVALID_TOKEN_CODES.has(result.error?.code)) {
        staleDeletes.push(chunk[resultIndex].ref.delete());
      }
    });
    await Promise.all(staleDeletes);
  }
}
