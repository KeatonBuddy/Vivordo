"use strict";

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");

const SCHEMA_VERSION = 1;

/**
 * Validate a canonical calendar-day document ID.
 * @param {string} day Day key.
 * @return {boolean} Whether the day exists.
 */
function validDay(day) {
  return typeof day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(day) &&
    !Number.isNaN(Date.parse(`${day}T00:00:00Z`)) &&
    new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) === day;
}

// V1 deliberately covers activity only. Never reconstruct source precedence,
// capacity baselines or detailed heart-rate insights from these three totals.
/**
 * Keep canonical totals without reinterpreting source precedence.
 * @param {object} data Current daily metrics.
 * @return {object} Compact activity projection.
 */
function projectActivity(data) {
  const result = {schemaVersion: SCHEMA_VERSION};
  for (const key of ["steps", "active_calories", "exercise_time"]) {
    const metric = data?.[key];
    const sum = metric?.sum;
    result[key] = {
      sum: typeof sum === "number" && Number.isFinite(sum) && sum >= 0 ?
        sum : null,
      source: typeof metric?.source === "string" ? metric.source : null,
    };
  }
  return result;
}

/**
 * Read CURRENT source inside a transaction, not the trigger's event payload.
 * The transaction serializes concurrent writers, source deletion/recreation,
 * and the existing account-deletion tombstone. Repeated/out-of-order events
 * converge to the latest source, with no timestamp-only projection writes.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {Function} timestamp Server timestamp factory.
 * @return {Promise<string>} Projection outcome.
 */
async function refreshActivitySummary(db, uid, day, timestamp) {
  if (!validDay(day)) return "ignored";
  const user = db.doc(`users/${uid}`);
  const source = user.collection("metrics_daily").doc(day);
  const target = user.collection("metric_summaries_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  return db.runTransaction(async (tx) => {
    const [owner, tombstone, current, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(source), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists || !current.exists) {
      if (existing.exists) tx.delete(target);
      return "deleted";
    }
    const projected = projectActivity(current.data());
    const old = existing.data();
    const oldContent = old ? {...old} : null;
    if (oldContent) delete oldContent.projectedAt;
    if (isDeepStrictEqual(projected, oldContent)) return "unchanged";
    // Replace rather than merge: removed fields must not survive a projection.
    tx.set(target, {...projected, projectedAt: timestamp()});
    return "written";
  });
}

module.exports = {
  SCHEMA_VERSION, validDay, projectActivity, refreshActivitySummary,
};
