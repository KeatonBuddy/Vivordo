"use strict";

const RECENT_AUTH_WINDOW_SECONDS = 10 * 60;

/**
 * Returns whether a callable authentication token is recent enough for an
 * irreversible account deletion.
 *
 * @param {object|undefined} auth Callable request authentication context.
 * @param {number} nowSeconds Current Unix time in seconds.
 * @param {number} windowSeconds Maximum accepted authentication age.
 * @return {boolean}
 */
function hasRecentAuthentication(
    auth,
    nowSeconds = Math.floor(Date.now() / 1000),
    windowSeconds = RECENT_AUTH_WINDOW_SECONDS,
) {
  const authenticatedAt = Number(auth?.token?.auth_time);
  return Number.isFinite(authenticatedAt) &&
    authenticatedAt <= nowSeconds &&
    nowSeconds - authenticatedAt <= windowSeconds;
}

/**
 * Removes a user ID from an array while preserving order and uniqueness.
 *
 * @param {unknown} values Candidate array.
 * @param {string} uid User ID to remove.
 * @return {Array<unknown>}
 */
function withoutUid(values, uid) {
  if (!Array.isArray(values)) return [];
  return [...new Set(values.filter((value) => value !== uid))];
}

/**
 * Builds the root challenge update required when one participant deletes
 * their Vivordo account.
 *
 * @param {object} challenge Existing challenge document.
 * @param {string} uid Deleted participant ID.
 * @param {number} participantProgress Progress stored on their participant.
 * @return {object} Challenge deletion instructions.
 */
function challengeDeletionPlan(challenge = {}, uid, participantProgress = 0) {
  const participantUids = withoutUid(challenge.participantUids, uid);
  if (participantUids.length === 0) {
    return {
      deleteChallenge: true,
      update: {},
      remainingParticipantUids: [],
      newCreatorUid: null,
    };
  }

  const participantNames = {...(challenge.participantNames || {})};
  delete participantNames[uid];
  let acceptedUids = withoutUid(challenge.acceptedUids, uid);
  let pendingUids = withoutUid(challenge.pendingUids, uid);
  const declinedUids = withoutUid(challenge.declinedUids, uid);
  const activeParticipantUids = withoutUid(
      challenge.activeParticipantUids,
      uid,
  );
  const completedUids = withoutUid(challenge.completedUids, uid);

  let newCreatorUid = null;
  let newCreatorWasPending = false;
  let creatorUid = challenge.creatorUid;
  let creatorName = challenge.creatorName;
  if (creatorUid === uid) {
    newCreatorUid = acceptedUids[0] || participantUids[0];
    newCreatorWasPending = pendingUids.includes(newCreatorUid);
    if (newCreatorWasPending) {
      acceptedUids = [...acceptedUids, newCreatorUid];
      pendingUids = withoutUid(pendingUids, newCreatorUid);
    }
    creatorUid = newCreatorUid;
    creatorName = participantNames[newCreatorUid] || "Circle member";
  }

  const currentProgress = Number(challenge.totalProgress || 0);
  const removedProgress = Number(participantProgress || 0);
  const update = {
    participantUids,
    participantNames,
    participantCount: participantUids.length,
    acceptedUids,
    pendingUids,
    declinedUids,
    activeParticipantUids,
    completedUids,
    creatorUid,
    creatorName,
    totalProgress: Math.max(0, currentProgress - removedProgress),
  };
  if (challenge.creatorUid === uid) update.message = null;

  if (participantUids.length < 2 &&
      ["pending", "active"].includes(challenge.status)) {
    update.status = "cancelled";
  }

  return {
    deleteChallenge: false,
    update,
    remainingParticipantUids: participantUids,
    newCreatorUid,
    newCreatorWasPending,
  };
}

module.exports = {
  RECENT_AUTH_WINDOW_SECONDS,
  challengeDeletionPlan,
  hasRecentAuthentication,
  withoutUid,
};
