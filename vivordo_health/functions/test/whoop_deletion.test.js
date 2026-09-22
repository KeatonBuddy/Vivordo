"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {whoopDeletionPlan} = require("../whoop_deletion");

test("removes WHOOP sleep without touching Apple activity", () => {
  const plan = whoopDeletionPlan({
    sleep: {avg: 7.5, source: "whoop"},
    steps: {sum: 9000, source: "apple_health"},
    wellness: {avg: 82, source: "computed"},
  });

  assert.equal(plan.changed, true);
  assert.deepEqual(plan.deletePaths.sort(), ["sleep", "wellness"]);
  assert.deepEqual(plan.setFields, {});
});

test("preserves non-WHOOP sleep and computed output", () => {
  const plan = whoopDeletionPlan({
    sleep: {avg: 8, source: "fitbit"},
    wellness: {avg: 90, source: "computed"},
  });

  assert.equal(plan.changed, false);
  assert.deepEqual(plan.deletePaths, []);
});

test("promotes Apple heart rate after removing active WHOOP Bluetooth", () => {
  const apple = {avg: 64, source: "apple_health"};
  const plan = whoopDeletionPlan({
    heart_rate: {avg: 72, source: "whoop_ble"},
    heart_rate_sources: {
      whoop_ble: {avg: 72, source: "whoop_ble"},
      apple_health: apple,
    },
    stress: {avg: 42, source: "baas_api"},
    wellness: {avg: 80, source: "computed"},
    heart_health: {avg: 88, source: "computed_personal_baseline"},
  });

  assert.deepEqual(plan.setFields.heart_rate, apple);
  assert.deepEqual(plan.deletePaths.sort(), [
    "heart_health",
    "heart_rate_sources.whoop_ble",
    "stress",
    "wellness",
  ]);
});

test("deletes canonical heart rate when WHOOP is the only source", () => {
  const plan = whoopDeletionPlan({
    heart_rate: {avg: 70, source: "whoop_ble"},
    heart_rate_sources: {
      whoop_ble: {avg: 70, source: "whoop_ble"},
    },
  });

  assert.deepEqual(plan.deletePaths.sort(), [
    "heart_rate",
    "heart_rate_sources",
  ]);
});

test("cleanup planning is idempotent", () => {
  const plan = whoopDeletionPlan({
    sleep: {avg: 7, source: "apple_health"},
    steps: {sum: 10000, source: "apple_health"},
  });

  assert.equal(plan.changed, false);
  assert.deepEqual(plan.deletePaths, []);
  assert.deepEqual(plan.setFields, {});
});
