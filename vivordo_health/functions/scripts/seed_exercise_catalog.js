/* eslint-disable */
// =============================================================================
// Uploads the default exercise catalog to exercise_catalog/current.
//
// exercise_catalog_seed.json is the source of truth. This script overwrites the
// document, so any Firebase console edit that was not mirrored back into the
// JSON is reverted by the next run.
//
// SAFETY: dry-run by default — prints what it would write and writes nothing.
//         Pass --apply to actually write.
//
// RUN (from the functions/ directory):
//   1. Authenticate Application Default Credentials, either:
//        gcloud auth application-default login
//      or set a service-account key:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//   2. Dry run:   node scripts/seed_exercise_catalog.js
//   3. Apply:     node scripts/seed_exercise_catalog.js --apply
// =============================================================================

const admin = require("firebase-admin");
const {buildCatalogDocument} = require("../exercise_catalog");
const entries = require("./exercise_catalog_seed.json");

admin.initializeApp({projectId: "vivordo-health"});
const db = admin.firestore();

const APPLY = process.argv.includes("--apply");
const REF = db.collection("exercise_catalog").doc("current");

async function main() {
  const existing = await REF.get();
  const version = existing.exists ? (existing.data().version || 0) + 1 : 1;
  const doc = buildCatalogDocument(entries, version);
  const bytes = Buffer.byteLength(JSON.stringify(doc));

  console.log(`entries : ${doc.exercises.length}`);
  console.log(`version : ${version}${existing.exists ? "" : " (new document)"}`);
  console.log(`size    : ${(bytes / 1024).toFixed(1)}KB of 1024KB`);

  if (!APPLY) {
    console.log("\nDry run. Re-run with --apply to write.");
    return;
  }

  await REF.set({
    ...doc,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("\nWrote exercise_catalog/current.");
}

main().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
