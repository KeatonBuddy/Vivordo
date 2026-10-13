"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  challengeDeletionPlan,
  hasRecentAuthentication,
  withoutUid,
} = require("../account_deletion");

test("recent authentication accepts only tokens within the window", () => {
  assert.equal(
      hasRecentAuthentication({token: {auth_time: 950}}, 1000, 60),
      true,
  );
  assert.equal(
      hasRecentAuthentication({token: {auth_time: 939}}, 1000, 60),
      false,
  );
  assert.equal(
      hasRecentAuthentication({token: {auth_time: 1001}}, 1000, 60),
      false,
  );
  assert.equal(hasRecentAuthentication(undefined, 1000, 60), false);
});

test("withoutUid removes duplicates of the deleted user", () => {
  assert.deepEqual(
      withoutUid(["a", "deleted", "a", "deleted"], "deleted"),
      ["a"],
  );
  assert.deepEqual(withoutUid(null, "deleted"), []);
});

test("challenge deletion transfers ownership and removes state", () => {
  const plan = challengeDeletionPlan({
    creatorUid: "deleted",
    creatorName: "Old creator",
    participantUids: ["deleted", "friend", "pending"],
    participantNames: {
      deleted: "Old creator",
      friend: "New creator",
      pending: "Invitee",
    },
    acceptedUids: ["deleted", "friend"],
    pendingUids: ["pending"],
    declinedUids: ["deleted"],
    activeParticipantUids: ["deleted", "friend"],
    completedUids: ["deleted"],
    totalProgress: 150,
    status: "active",
  }, "deleted", 40);

  assert.equal(plan.deleteChallenge, false);
  assert.equal(plan.newCreatorUid, "friend");
  assert.equal(plan.update.creatorUid, "friend");
  assert.equal(plan.update.creatorName, "New creator");
  assert.equal(plan.update.message, null);
  assert.equal(plan.update.totalProgress, 110);
  assert.equal(plan.update.participantCount, 2);
  assert.deepEqual(plan.update.participantUids, ["friend", "pending"]);
  assert.equal(plan.update.participantNames.deleted, undefined);
});

test("challenge deletion cancels one-person active challenges", () => {
  const plan = challengeDeletionPlan({
    creatorUid: "friend",
    participantUids: ["friend", "deleted"],
    participantNames: {friend: "Friend", deleted: "Deleted"},
    acceptedUids: ["friend", "deleted"],
    activeParticipantUids: ["friend", "deleted"],
    totalProgress: 25,
    status: "active",
  }, "deleted", 10);

  assert.equal(plan.deleteChallenge, false);
  assert.equal(plan.update.status, "cancelled");
  assert.equal(plan.update.totalProgress, 15);
});

test("challenge deletion removes an empty challenge", () => {
  const plan = challengeDeletionPlan({
    creatorUid: "deleted",
    participantUids: ["deleted"],
  }, "deleted");
  assert.equal(plan.deleteChallenge, true);
});

test("challenge deletion promotes a pending member when needed", () => {
  const plan = challengeDeletionPlan({
    creatorUid: "deleted",
    participantUids: ["deleted", "invitee", "other"],
    participantNames: {invitee: "Invitee", other: "Other"},
    acceptedUids: ["deleted"],
    pendingUids: ["invitee", "other"],
    status: "pending",
  }, "deleted");

  assert.equal(plan.newCreatorUid, "invitee");
  assert.equal(plan.newCreatorWasPending, true);
  assert.deepEqual(plan.update.acceptedUids, ["invitee"]);
  assert.deepEqual(plan.update.pendingUids, ["other"]);
});
