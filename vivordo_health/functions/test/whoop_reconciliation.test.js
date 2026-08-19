"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  shouldDeleteWhoopSleep,
  whoopPresentSleepDays,
  whoopReconciliationDays,
} = require("../whoop_reconciliation");

test("morning reconciliation preserves today", () => {
  assert.deepEqual(whoopReconciliationDays({
    localDate: "2026-08-19",
    daysBack: 2,
    includeCurrentDay: false,
  }), ["2026-08-18"]);
});

test("midday reconciliation includes today", () => {
  assert.deepEqual(whoopReconciliationDays({
    localDate: "2026-08-19",
    daysBack: 2,
    includeCurrentDay: true,
  }), ["2026-08-19", "2026-08-18"]);
});

test("manual history reconciles completed days in its local window", () => {
  const days = whoopReconciliationDays({
    localDate: "2026-08-19",
    daysBack: 30,
    includeCurrentDay: false,
  });
  assert.equal(days.length, 29);
  assert.equal(days[0], "2026-08-18");
  assert.equal(days.at(-1), "2026-07-21");
});

test("unscored records still protect their wake day", () => {
  const days = whoopPresentSleepDays([{
    end: "2026-08-19T07:00:00.000Z",
    timezone_offset: "-06:00",
    score_state: "PENDING_SCORE",
  }]);
  assert.deepEqual([...days], ["2026-08-19"]);
});

test("only missing WHOOP sleep is deleted", () => {
  assert.equal(shouldDeleteWhoopSleep({source: "whoop"}, false), true);
  assert.equal(shouldDeleteWhoopSleep({source: "whoop"}, true), false);
  assert.equal(shouldDeleteWhoopSleep({source: "apple_health"}, false), false);
  assert.equal(shouldDeleteWhoopSleep({source: "fitbit"}, false), false);
});

test("a moved record leaves its old day eligible for removal", () => {
  const present = whoopPresentSleepDays([{
    end: "2026-08-19T14:00:00.000Z",
    timezone_offset: "-06:00",
    score_state: "SCORED",
  }]);
  assert.equal(present.has("2026-08-19"), true);
  assert.equal(present.has("2026-08-18"), false);
  assert.equal(shouldDeleteWhoopSleep({source: "whoop"}, false), true);
});
