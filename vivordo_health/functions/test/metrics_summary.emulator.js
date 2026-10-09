"use strict";
/* eslint-disable max-len, require-jsdoc */
// Run via firebase emulators:exec --only firestore --project demo-vivordo-performance.
// Guard before initializing any SDK: this script must NEVER contact production.
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {refreshActivitySummary} = require("../metrics_summary");
const project = "demo-vivordo-performance";
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host || !/^(127\.0\.0\.1|localhost):\d+$/.test(host)) {
  throw new Error("A local Firestore emulator is required");
}
admin.initializeApp({projectId: project});
const db = admin.firestore();
const root = `http://${host}/v1/projects/${project}/databases/(default)/documents`;

function token(uid) {
  // Unsigned identity tokens are accepted ONLY by the emulator.
  const encode = (data) => Buffer.from(JSON.stringify(data)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  return `${encode({alg: "none", typ: "JWT"})}.${encode({
    sub: uid, user_id: uid, aud: project,
    iss: `https://securetoken.google.com/${project}`,
    iat: now, exp: now + 3600,
    firebase: {sign_in_provider: "custom"},
  })}.`;
}

async function request(path, uid, method = "GET") {
  const headers = {"Content-Type": "application/json"};
  if (uid) headers.Authorization = `Bearer ${token(uid)}`;
  return fetch(`${root}/${path}`, {
    method, headers,
    ...(method === "PATCH" ? {body: JSON.stringify({fields: {}})} : {}),
  });
}

async function main() {
  const uid = `summary-test-${crypto.randomUUID()}`;
  const base = `users/${uid}`;
  const day = "2026-09-24";
  const source = db.doc(`${base}/metrics_daily/${day}`);
  const summary = db.doc(`${base}/metric_summaries_daily/${day}`);
  const marker = db.doc(`${base}/metrics_summary_migrations/v1`);
  const tombstone = db.doc(`account_deletion_jobs/${crypto.createHash("sha256").update(uid).digest("hex")}`);
  try {
    await db.doc(base).set({});
    await source.set({steps: {sum: 100}});
    const refresh = () => refreshActivitySummary(db, uid, day,
        () => admin.firestore.FieldValue.serverTimestamp());
    await refresh();
    await marker.set({enabled: false, schemaVersion: 1});
    for (const path of [summary.path, marker.path]) {
      assert.equal((await request(path, uid)).status, 200, "owner read");
      assert.equal((await request(path, "stranger")).status, 403, "cross-user read denied");
      assert.equal((await request(path, null)).status, 403, "anonymous read denied");
      assert.equal((await request(path, uid, "PATCH")).status, 403, "owner update denied");
      assert.equal((await request(path, uid, "DELETE")).status, 403, "owner delete denied");
      assert.equal((await request(`${path}-new`, uid, "PATCH")).status, 403, "owner create denied");
    }
    assert.equal((await request(`${summary.path}/nested/test`, uid, "PATCH")).status, 403);
    assert.equal((await request(source.path, uid)).status, 200, "legacy read preserved");
    assert.equal((await request(`${base}/metrics_daily/2026-09-23`, uid, "PATCH")).status, 200,
        "legacy write preserved");

    // Real optimistic transactions: overlapping updates must settle on the
    // current source, not the value from whichever event happened last.
    await Promise.all([
      refresh(),
      source.set({steps: {sum: 250}}).then(refresh),
    ]);
    assert.equal((await summary.get()).data().steps.sum, 250);
    const before = (await summary.get()).data().projectedAt;
    await Promise.all([refresh(), refresh()]);
    assert.ok((await summary.get()).data().projectedAt.isEqual(before));
    await Promise.all([refresh(), source.delete().then(refresh)]);
    assert.equal((await summary.get()).exists, false);
    await source.set({steps: {sum: 75}});
    await refresh();
    assert.equal((await summary.get()).data().steps.sum, 75);
    await Promise.all([refresh(), tombstone.set({status: "running"}).then(refresh)]);
    assert.equal((await summary.get()).exists, false);
    console.log("Emulator passed: owner-only reads, server-only writes, legacy access, concurrent projection/deletion.");
  } finally {
    await db.recursiveDelete(db.doc(base));
    await tombstone.delete();
    await admin.app().delete();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
