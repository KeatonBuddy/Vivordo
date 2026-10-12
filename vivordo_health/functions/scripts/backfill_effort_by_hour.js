"use strict";

// Re-places activity in the last 28 days' Effort running totals
// (`effort.byHour`), so Home's "So far" compares today with days measured
// the same way: activity at the hour it happened, not all at the end.
// Dry-run by default.
// Usage: node scripts/backfill_effort_by_hour.js PROJECT UID [--apply]
// or:    node scripts/backfill_effort_by_hour.js PROJECT --all-users [--apply]
// Deploy computeDailyCapacity (effort.js) FIRST, so new days are written the
// new way. Locked days keep their totals: only byHour and usualCalories are
// rewritten, and a day whose inputs changed since it locked (a different
// total) is skipped.
const admin = require("firebase-admin");
const {isDeepStrictEqual} = require("node:util");
const {effortFor} = require("../effort");

const DAYS = 28;

/**
 * Backfill one account.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {boolean} apply Write the changes.
 * @return {Promise<object>} Outcome counts.
 */
async function backfill(db, uid, apply) {
  const counts = {};
  const now = new Date();
  for (let k = 1; k <= DAYS; k++) {
    const day = new Date(now.getTime() - k * 86400000)
        .toISOString().slice(0, 10);
    const ref = db.doc(`users/${uid}/scores_daily/${day}`);
    const stored = (await ref.get()).data()?.effort;
    let outcome;
    if (!stored?.byHour) {
      outcome = "no effort";
    } else {
      const {effort} = await effortFor(db, uid, day, now);
      if (!effort) {
        outcome = "no inputs";
      } else if (Math.abs(effort.total - stored.total) > 0.05) {
        outcome = "inputs changed, skipped";
      } else if (isDeepStrictEqual(effort.byHour, stored.byHour) &&
          effort.usualCalories === (stored.usualCalories ?? null)) {
        outcome = "unchanged";
      } else {
        if (apply) {
          await ref.update({
            "effort.byHour": effort.byHour,
            "effort.usualCalories": effort.usualCalories,
          });
        }
        outcome = apply ? "rewritten" : "would rewrite";
      }
    }
    counts[outcome] = (counts[outcome] ?? 0) + 1;
  }
  return counts;
}

/** Run an explicitly requested backfill. */
async function main() {
  const [projectId, target, ...flags] = process.argv.slice(2);
  if (!projectId || !target || target.includes("/") ||
      flags.some((f) => f !== "--apply")) {
    throw new Error("Expected PROJECT (UID | --all-users) [--apply]");
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();
  const apply = flags.includes("--apply");
  const uids = target === "--all-users" ?
    (await db.collection("users").listDocuments()).map((d) => d.id) :
    [target];
  const total = {};
  for (const uid of uids) {
    const counts = await backfill(db, uid, apply);
    for (const [k, v] of Object.entries(counts)) total[k] = (total[k] ?? 0) + v;
    if (uids.length === 1) console.log(JSON.stringify(counts));
  }
  console.log(`${uids.length} account(s): ${JSON.stringify(total)}`);
  if (!apply) console.log("Dry run: nothing written.");
}

main().catch((error) => {
  console.error(error.message); process.exitCode = 1;
});
