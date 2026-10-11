"use strict";

// Lifetime summary backfill for achievement readers. Dry-run by default.
// Usage: node scripts/backfill_achievement_summaries.js PROJECT UID
//   [--apply] [--verify] [--enable]
// or:    node scripts/backfill_achievement_summaries.js PROJECT --all-users
//   [--apply] [--enable]
// Deploy projectDailyActivitySummary with scan/mood counts FIRST, so days
// written during or after the run are projected by the trigger.
//   --apply   re-project every day that has a metrics or summary document.
//   --verify  compare every summary with its current source; fail on drift.
//   --enable  verify, then switch the account's achievement reader on.
//   --all-users  run for every account not already enabled; accounts that
//             fail are listed and left on full history.
// Rollback: set `enabled: false` on the marker; readers fall back to
// metrics_daily on their next session.
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {validDay, projectActivity, refreshActivitySummary} =
  require("../metrics_summary");

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Run the requested steps for one account.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string[]} flags Requested steps.
 * @param {Function} log Progress output.
 * @return {Promise<string[]>} Mismatches; empty when every check passed.
 */
async function migrateAccount(db, uid, flags, log) {
  const user = db.doc(`users/${uid}`);
  const sources = user.collection("metrics_daily");
  const summaries = user.collection("metric_summaries_daily");
  const marker = user.collection("metrics_summary_migrations")
      .doc("achievements");
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();

  /**
   * Write the marker only for an account that is not being deleted.
   * @param {object} data Marker fields.
   */
  async function setMarker(data) {
    await db.runTransaction(async (tx) => {
      const [owner, tombstone] = await Promise.all([
        tx.get(user), tx.get(deletion),
      ]);
      if (!owner.exists || tombstone.exists) {
        throw new Error("Account unavailable/deleting");
      }
      tx.set(marker, {...data, updatedAt: stamp()}, {merge: true});
    });
  }

  const ids = new Set([
    ...(await sources.listDocuments()).map((d) => d.id),
    ...(await summaries.listDocuments()).map((d) => d.id),
  ]);
  const days = [...ids].filter(validDay).sort();
  log(`${days.length} days (${days[0] ?? "-"} to ${days.at(-1) ?? "-"}).`);

  if (flags.includes("--apply")) {
    await setMarker({status: "running", enabled: false});
    for (const day of days) {
      await refreshActivitySummary(db, uid, day, stamp);
      // Pace writes; this is operator tooling, never run from the app.
      await pause(100);
    }
    await setMarker({status: "complete", enabled: false});
    log("Backfill complete; reader still disabled.");
  }

  if (!flags.includes("--verify") && !flags.includes("--enable")) return [];
  const problems = [];
  const [sourceSnap, summarySnap] = await Promise.all([
    sources.get(), summaries.get(),
  ]);
  const stored = new Map(summarySnap.docs.map((d) => [d.id, d.data()]));
  for (const doc of sourceSnap.docs) {
    const expected = projectActivity(doc.data());
    if (!validDay(doc.id)) {
      // The legacy reader counts every document; summaries only days.
      if (expected.scans || expected.moods ||
          ["steps", "active_calories", "exercise_time"]
              .some((k) => expected[k].sum !== null)) {
        problems.push(`${doc.id}: non-day document with achievement data`);
      }
      continue;
    }
    const actual = {...stored.get(doc.id)};
    delete actual.projectedAt;
    stored.delete(doc.id);
    if (!isDeepStrictEqual(expected, actual)) {
      problems.push(`${doc.id}: summary differs from source`);
    }
  }
  for (const day of stored.keys()) {
    problems.push(`${day}: summary without a source day`);
  }
  if (problems.length > 0) return problems;
  log(`Verified ${sourceSnap.size} source documents.`);

  if (flags.includes("--enable")) {
    if ((await marker.get()).data()?.status !== "complete") {
      return ["backfill has not completed; run --apply first"];
    }
    await setMarker({enabled: true});
    log("Achievement summary reader enabled.");
  }
  return [];
}

/** Run an explicitly requested migration. */
async function main() {
  const [projectId, target, ...flags] = process.argv.slice(2);
  const known = ["--apply", "--verify", "--enable"];
  const allUsers = target === "--all-users";
  if (!projectId || !target || target.includes("/") ||
      (!allUsers && target.startsWith("--")) ||
      flags.some((f) => !known.includes(f))) {
    throw new Error("Expected PROJECT (UID | --all-users) " +
      "[--apply] [--verify] [--enable]");
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();

  if (!allUsers) {
    if (flags.length === 0) console.log("Dry run: nothing written.");
    const problems = await migrateAccount(db, target, flags, console.log);
    for (const problem of problems) console.log(problem);
    if (problems.length > 0) {
      // A write landing mid-check shows up here too; re-run to confirm.
      throw new Error(`${problems.length} mismatches; reader left disabled.`);
    }
    return;
  }

  const users = await db.collection("users").listDocuments();
  const pending = [];
  for (const user of users) {
    const marker = await user.collection("metrics_summary_migrations")
        .doc("achievements").get();
    if (marker.data()?.enabled !== true) pending.push(user.id);
  }
  console.log(`${users.length} accounts; ${users.length - pending.length} ` +
    `already enabled; ${pending.length} to migrate.`);
  if (flags.length === 0) {
    console.log("Dry run: nothing written.");
    return;
  }

  const failed = [];
  for (const [index, uid] of pending.entries()) {
    const log = (line) => console.log(`[${index + 1}/${pending.length}] ` +
      `${uid}: ${line}`);
    try {
      const problems = await migrateAccount(db, uid, flags, log);
      if (problems.length > 0) {
        log(`${problems.length} mismatches, left on full history ` +
          `(first: ${problems[0]})`);
        failed.push(uid);
      }
    } catch (error) {
      log(`failed: ${error.message}`);
      failed.push(uid);
    }
  }
  console.log(`Done: ${pending.length - failed.length} succeeded, ` +
    `${failed.length} left on full history.`);
  if (failed.length > 0) {
    // Usually a write landed mid-check; re-running retries only these.
    console.log(`Re-run to retry: ${failed.join(" ")}`);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error.message); process.exitCode = 1;
});
