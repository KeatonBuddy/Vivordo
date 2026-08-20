"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  calculateHeartHealthScore,
} = require("../heart_health_score");

const baseline = (days = 14) => Array.from({length: days}, () => ({
  restingHeartRate: 64,
  hrvSdnn: 48,
  quietHeartRate: 66,
}));

test("centers a user's personal baseline at 80", () => {
  const result = calculateHeartHealthScore({
    restingHeartRate: 64,
    hrvSdnn: 48,
    quietHeartRate: 66,
  }, baseline());

  assert.equal(result.score, 80);
  assert.equal(result.scoredSignals, 3);
  assert.equal(result.confidence, "high");
});

test("rewards favorable personalized trends", () => {
  const result = calculateHeartHealthScore({
    restingHeartRate: 61,
    hrvSdnn: 53,
    quietHeartRate: 63,
  }, baseline());

  assert.ok(result.score > 90);
});

test("reduces the score when signals move below the usual trend", () => {
  const result = calculateHeartHealthScore({
    restingHeartRate: 70,
    hrvSdnn: 38,
    quietHeartRate: 72,
  }, baseline());

  assert.ok(result.score < 60);
});

test("redistributes weight when a signal is unavailable", () => {
  const history = baseline().map(({restingHeartRate, hrvSdnn}) => ({
    restingHeartRate,
    hrvSdnn,
  }));
  const result = calculateHeartHealthScore({
    restingHeartRate: 64,
    hrvSdnn: 48,
  }, history);

  assert.equal(result.score, 80);
  assert.equal(result.scoredSignals, 2);
  assert.equal(result.confidence, "medium");
});

test("builds a baseline before returning a score", () => {
  const result = calculateHeartHealthScore({restingHeartRate: 64}, baseline(6));

  assert.equal(result.score, null);
  assert.equal(result.isBuildingBaseline, true);
  assert.equal(result.baselineDays, 6);
});
