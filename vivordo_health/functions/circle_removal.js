"use strict";
const {challengeDeletionPlan} = require("./account_deletion");

/**
 * Plan departure without deleting posts or other participants' progress.
 * @param {object} challenge Shared challenge.
 * @param {string} uid Departing user.
 * @param {number} progress Departing user's progress.
 * @return {object} Root update.
 */
function removalPlan(challenge, uid, progress) {
  if (challenge.participantUids.length <= 2) {
    return {
      status: "cancelled", participantUids: [], participantCount: 0,
      acceptedUids: [], pendingUids: [], activeParticipantUids: [],
    };
  }
  return challengeDeletionPlan(challenge, uid, progress).update;
}
module.exports = {removalPlan};
