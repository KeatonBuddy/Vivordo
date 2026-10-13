"use strict";

// Emails each new Circle abuse report to the support inbox, so reports are
// acted on within a day (App Review Guideline 1.2) without watching the
// console.

const REPORT_EMAIL = "contact.vivordo@gmail.com";

const WHAT = {
  comment: "Feed comment",
  profile: "Profile",
  challenge: "Challenge note",
  challenge_comment: "Challenge comment",
};

/**
 * The alert for one report: subject and plain-text body with what was
 * reported, why, and where to find it.
 * @param {string} reportId The reports/{id} document id.
 * @param {object} report Its data.
 * @return {{subject: string, text: string}} The email.
 */
function reportEmail(reportId, report) {
  const what = WHAT[report.type] ?? "Feed post";
  const reason = String(report.reason ?? "other").replace(/_/g, " ");
  const author = report.commentAuthorUid ?? report.authorUid ??
    report.profileOwnerUid ?? report.postOwnerUid;
  const where = [
    report.postOwnerUid && `Post: users/${report.postOwnerUid}/` +
      `circle_activity/${report.postId}`,
    report.challengeId && `Challenge: challenges/${report.challengeId}`,
    report.commentId && `Comment: ${report.commentId}`,
  ].filter(Boolean);
  return {
    subject: `Vivordo report: ${what} · ${reason}`,
    text: [
      `${what} reported for ${reason}.`,
      "",
      `Details: ${report.details?.trim() || "(none)"}`,
      `Reported user: ${author ?? "unknown"}`,
      `Reporter: ${report.reporterUid}`,
      ...where,
      "",
      "Review it within 24 hours: https://console.firebase.google.com/" +
        `project/vivordo-health/firestore/data/~2Freports~2F${reportId}`,
    ].join("\n"),
  };
}

module.exports = {REPORT_EMAIL, reportEmail};
