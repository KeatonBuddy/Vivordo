"use strict";

// Recalculates every stored Physical Health day with the current formula
// (version 2: the guideline scores 80, going beyond it 100), so the trend
// and "vs 4 weeks ago" compare like with like instead of showing a drop on
// the day the formula changed. Physical Health days aren't locked.
// Dry-run by default.
// Usage: node scripts/backfill_physical_health.js PROJECT UID [--apply]
// or:    node scripts/backfill_physical_health.js PROJECT --all-users [--apply]
// Deploy computeDailyCapacity (physical_health.js) FIRST, so new days are
// written the new way.
const admin = require("firebase-admin");
const {VERSION, refreshPhysicalHealth} = require("../physical_health");

/**
 * Backfill one account.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {boolean} apply Write the changes.
 * @return {Promise<object>} Outcome counts.
 */
async function backfill(db, uid, apply) {
  const scores = await db.collection(`users/${uid}/scores_daily`)
      .select("physical").get();
  const days = scores.docs
      .filter((d) => d.get("physical") &&
        d.get("physical").version !== VERSION)
      .map((d) => d.id).sort();
  if (!apply) return {"would recalculate": days.length};
  const counts = {};
  for (const day of days) {
    const outcome = await refreshPhysicalHealth(db, uid, day,
        () => admin.firestore.FieldValue.serverTimestamp());
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
  }
  console.log(`${uids.length} account(s): ${JSON.stringify(total)}`);
  if (!apply) console.log("Dry run: nothing written.");
}

main().catch((error) => {
  console.error(error.message); process.exitCode = 1;
});
