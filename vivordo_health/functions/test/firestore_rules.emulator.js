"use strict";

// Circle friendship rules, checked in the Firestore emulator (never prod):
//   cd vivordo_health && firebase emulators:exec --only firestore \
//     --project demo-vivordo "node functions/test/firestore_rules.emulator.js"

const assert = require("node:assert");

const PROJECT = "demo-vivordo";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const API = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/${ROOT}`;
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
// The emulator accepts unsigned tokens; "owner" bypasses rules for seeding.
const token = (uid) => uid === "admin" ? "owner" :
  `${b64({alg: "none", typ: "JWT"})}.${b64({
    sub: uid, user_id: uid, aud: PROJECT, iat: 1, exp: 9999999999,
    iss: `https://securetoken.google.com/${PROJECT}`,
  })}.`;
const fields = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) =>
  [k, typeof v === "number" ? {integerValue: v} : {stringValue: v}]));
const call = async (uid, method, url, body) => (await fetch(url, {
  method,
  headers: {"Authorization": `Bearer ${token(uid)}`,
    "Content-Type": "application/json"},
  body: body && JSON.stringify(body),
})).status;
const put = (uid, path, data) =>
  call(uid, "PATCH", `${API}/${path}`, {fields: fields(data)});
const get = (uid, path) => call(uid, "GET", `${API}/${path}`);
const del = (uid, path) => call(uid, "DELETE", `${API}/${path}`);
const rel = (owner, kind, other) =>
  `users/${owner}/circle/relationships/${kind}/${other}`;

(async () => {
  const day = "users/victim/circle_daily/2026-11-12";
  await put("admin", day, {steps: 9000});

  // A stranger can't forge a request, a friendship on either side, or medals.
  assert.equal(await get("attacker", day), 403);
  assert.equal(await put("attacker", rel("attacker", "friend_requests",
      "victim"), {fromUid: "victim", toUid: "attacker"}), 403);
  assert.equal(await put("attacker", rel("victim", "friends", "attacker"),
      {uid: "attacker"}), 403);
  assert.equal(await put("attacker", rel("attacker", "friends", "victim"),
      {uid: "victim"}), 403);
  assert.equal(await put("attacker", "users/attacker/circle/profile",
      {challengeMedalCount: 99}), 403);
  assert.equal(await get("attacker", day), 403);

  // The real flow: bob asks, alice accepts in one batch (as the app does).
  assert.equal(await put("bob", rel("alice", "friend_requests", "bob"),
      {fromUid: "bob", toUid: "alice"}), 200);
  const write = (path, data) =>
    ({update: {name: `${ROOT}/${path}`, fields: fields(data)}});
  assert.equal(await call("alice", "POST", `${API}:commit`, {writes: [
    write(rel("alice", "friends", "bob"), {uid: "bob"}),
    write(rel("bob", "friends", "alice"), {uid: "alice"}),
    {delete: `${ROOT}/${rel("alice", "friend_requests", "bob")}`},
  ]}), 200);
  await put("alice", "users/alice/circle_daily/2026-11-12", {steps: 1});
  assert.equal(await get("bob", "users/alice/circle_daily/2026-11-12"), 200);
  assert.equal(await get("alice", rel("alice", "friends", "bob")), 200);

  // Declining, and the owner's own profile, still work.
  assert.equal(await put("bob", rel("carol", "friend_requests", "bob"),
      {fromUid: "bob", toUid: "carol"}), 200);
  assert.equal(await del("carol", rel("carol", "friend_requests", "bob")), 200);
  assert.equal(await put("alice", "users/alice/circle/profile",
      {username: "alice", challengeMedalCount: 0}), 200);
  assert.equal(await put("alice", "users/alice/circle/profile",
      {username: "alice2", challengeMedalCount: 0}), 200);
  // A new profile photo must be one of the app's own uploads.
  assert.equal(await put("alice", "users/alice/circle/profile", {
    username: "alice2", challengeMedalCount: 0,
    photoUrl: "https://tracker.example/pixel.png"}), 403);
  assert.equal(await put("alice", "users/alice/circle/profile", {
    username: "alice2", challengeMedalCount: 0, photoUrl:
      "https://firebasestorage.googleapis.com/v0/b/x/o/circle_profiles%2Fa"}),
  200);
  assert.equal(await put("alice", "rate_limits/alice_social", {count: 0}), 403);
  console.log("firestore rules: ok");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
