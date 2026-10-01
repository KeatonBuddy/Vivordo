"use strict";

// Recalculates Capacity for every day of one account. Dry-run by default.
// Usage: node scripts/backfill_capacity.js PROJECT UID [--apply]
// Past days come out final (they're over in every time zone). Run it after
// deploying computeDailyCapacity, which keeps today's score current.
const admin = require("firebase-admin");
const {validDay} = require("../metrics_summary");
const {refreshCapacity} = require("../capacity");

/** Run an explicitly requested backfill. */
async function main() {
  const [projectId, uid, ...flags] = process.argv.slice(2);
  if (!projectId || !uid || uid.includes("/") ||
      flags.some((f) => f !== "--apply")) {
    throw new Error("Expected PROJECT UID [--apply]");
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();
  const days = (await db.collection(`users/${uid}/metrics_daily`)
      .listDocuments()).map((d) => d.id).filter(validDay).sort();
  console.log(`${days.length} days (${days[0] ?? "-"} to ` +
    `${days.at(-1) ?? "-"}).`);
  if (!flags.includes("--apply")) {
    console.log("Dry run: nothing written.");
    return;
  }
  const counts = {};
  for (const day of days) {
    const outcome = await refreshCapacity(db, uid, day,
        () => admin.firestore.FieldValue.serverTimestamp());
    counts[outcome] = (counts[outcome] ?? 0) + 1;
  }
  console.log(JSON.stringify(counts));
}

main().catch((error) => {
  console.error(error.message); process.exitCode = 1;
});
