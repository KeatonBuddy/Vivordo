const {test} = require("node:test");
const assert = require("node:assert/strict");
const {removalPlan} = require("../circle_removal");

test("two-person challenges are cancelled with no remaining access", () => {
  const plan = removalPlan({participantUids: ["a", "b"]}, "a", 5);
  assert.equal(plan.status, "cancelled");
  assert.deepEqual(plan.participantUids, []);
  assert.deepEqual(plan.activeParticipantUids, []);
});

test("group departure keeps remaining members and their progress", () => {
  const plan = removalPlan({
    participantUids: ["a", "b", "c"], creatorUid: "a",
    acceptedUids: ["a", "b", "c"], activeParticipantUids: ["a", "b", "c"],
    participantNames: {a: "A", b: "B", c: "C"},
    status: "active", totalProgress: 30,
  }, "a", 10);
  assert.deepEqual(plan.participantUids, ["b", "c"]);
  assert.equal(plan.creatorUid, "b");
  assert.equal(plan.totalProgress, 20);
  assert.equal(plan.status, undefined);
});
