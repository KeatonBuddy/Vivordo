"use strict";

// Explicit single-account/date-window operator tool. Dry-run by default.
// Usage: node scripts/backfill_activity_summaries.js PROJECT UID START END
// Optional flags: --apply --restart
// Never auto-enables readers. Re-running resumes from the saved cursor; pass
// --restart for a complete reconciliation (including deleted source days).
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {validDay, refreshActivitySummary} = require("../metrics_summary");

/** Run a bounded, explicitly requested migration. */
async function main() {
  const [projectId, uid, start, end, ...flags] = process.argv.slice(2);
  if (!projectId || !uid || uid.includes("/") || !validDay(start) ||
      !validDay(end) || end < start ||
      flags.some((f) => !["--apply", "--restart"].includes(f))) {
    throw new Error("Expected PROJECT UID START END [--apply] [--restart]");
  }
  const days = [];
  for (let date = new Date(`${start}T00:00:00Z`);
    date.toISOString().slice(0, 10) <= end;
    date.setUTCDate(date.getUTCDate() + 1)) {
    days.push(date.toISOString().slice(0, 10));
    if (days.length > 90) throw new Error("At most 90 days per run");
  }
  if (!flags.includes("--apply")) {
    console.log(`Dry run: ${days.length} days; no database access or writes.`);
    return;
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();
  const user = db.doc(`users/${uid}`);
  const marker = user.collection("metrics_summary_migrations").doc("v1");
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  const stamp = () => admin.firestore.FieldValue.serverTimestamp();
  const saved = (await marker.get()).data();
  const resume = !flags.includes("--restart") && saved?.startDay === start &&
    saved?.endDay === end ? saved.cursor : null;
  /**
   * Persist progress only for an account that is not being deleted.
   * @param {object} data Cursor and migration status.
   */
  async function checkpoint(data) {
    await db.runTransaction(async (tx) => {
      const [owner, tombstone] = await Promise.all([
        tx.get(user), tx.get(deletion),
      ]);
      if (!owner.exists || tombstone.exists) {
        throw new Error("Account unavailable/deleting");
      }
      tx.set(marker, {schemaVersion: 1, startDay: start, endDay: end,
        enabled: false, updatedAt: stamp(), ...data});
    });
  }
  await checkpoint({status: "running", cursor: resume ?? null});
  for (const day of days) {
    if (resume && day <= resume) continue;
    await refreshActivitySummary(db, uid, day, stamp);
    await checkpoint({status: "running", cursor: day});
    // Pace writes; this is operator tooling, never run from screen startup.
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  await checkpoint({status: "complete", cursor: end});
  console.log("Backfill complete; readers disabled pending verification.");
}

main().catch((error) => {
  console.error(error.message); process.exitCode = 1;
});
