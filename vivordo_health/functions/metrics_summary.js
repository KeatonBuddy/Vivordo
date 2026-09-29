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

/**
 * Entry count, or 1 for a legacy single-value day. Must match
 * projectAchievementDay in lib/src/services/achievement_inputs.dart; both
 * sides are checked against test/achievement_count_cases.json.
 * @param {object} metric Metric map.
 * @param {boolean} legacy Whether a pre-entries value is present.
 * @return {number} Count.
 */
function countEntries(metric, legacy) {
  const entries = metric?.entries;
  return Array.isArray(entries) && entries.length > 0 ?
    entries.length : legacy ? 1 : 0;
}

// Activity totals plus achievement scan/mood counts. The counts are additive
// fields on schema 1: Fitness ignores them, and achievement readers treat a
// document without them as not yet projected. Never reconstruct source
// precedence, capacity baselines or heart-rate insights from these values.
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
  const scan = data?.heart_rate_scan;
  const mood = data?.mood;
  result.scans = countEntries(scan,
      scan?.source === "camera_ppg" || typeof scan?.avg === "number");
  result.moods = countEntries(mood,
      typeof mood?.avg === "number" || typeof mood?.label === "string");
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

/**
 * Switch the achievement summary reader on for an account with no daily
 * metrics yet. Every day written after projectDailyActivitySummary was
 * deployed gets a summary from the trigger, so only days that already exist
 * can be missing one. Accounts with days are left to the verified backfill
 * (scripts/backfill_achievement_summaries.js --all-users).
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {Function} timestamp Server timestamp factory.
 * @return {Promise<string>} Outcome.
 */
async function enableSummariesForNewAccount(db, uid, timestamp) {
  const user = db.doc(`users/${uid}`);
  const marker = user.collection("metrics_summary_migrations")
      .doc("achievements");
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  return db.runTransaction(async (tx) => {
    const [owner, tombstone, existing, days] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(marker),
      tx.get(user.collection("metrics_daily").limit(1)),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    if (existing.exists) return "unchanged";
    if (!days.empty) return "has-history";
    tx.set(marker, {status: "complete", enabled: true, scope: "new-account",
      updatedAt: timestamp()});
    return "enabled";
  });
}

module.exports = {
  SCHEMA_VERSION, validDay, projectActivity, refreshActivitySummary,
  enableSummariesForNewAccount,
};
