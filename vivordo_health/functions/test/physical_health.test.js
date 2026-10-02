"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {computePhysicalHealth, estimateVo2Max, vo2Median, physicalInputsChanged} = require("../physical_health");

// 28 days: ~30 min of exercise and 7,000 steps a day, 7.5 h of sleep with a
// bedtime around 23:00.
const days = (overrides = {}, count = 28) => Array.from({length: count}, (_, i) => ({
  steps: 7000, exerciseMinutes: 30, sleepHours: 7.5, bedtimeMin: 23 * 60 + (i % 3) * 10,
  checkInSleep: null, ...overrides,
}));
const strength = (n) => Array.from({length: n}, () => ({name: "Workout", exerciseCategories: ["Legs", "Chest"]}));
const profile = {age: 35, sex: "male", heightCm: 180, weightKg: 80};

test("a fairly active person with a watch VO2 max", () => {
  const result = computePhysicalHealth({
    days: days(), workouts: strength(6), logsWorkouts: true,
    vo2: {value: 41, source: "apple_health"}, profile,
  });
  // 210 min/week → 100; 7,000 steps → 87.5; 1.5 strength/week → 75;
  // VO2 41 vs median 41 (30s, male) → 60; sleep 7.5 h, regular → 100.
  assert.deepEqual(result.parts, {activeMinutes: 100, movement: 87.5, strength: 75, cardio: 60, sleep: 100});
  assert.equal(result.score, Math.round((30 * 100 + 15 * 87.5 + 20 * 75 + 20 * 60 + 15 * 100) / 100));
  assert.equal(result.label, "good");
  assert.equal(result.details.vo2Source, "apple_health");
});

test("without a measured VO2 max it's estimated from age, sex, BMI and activity", () => {
  // Jackson: 56.363 + 1.921 × 7 − 0.381 × 35 − 0.754 × 24.69 + 10.987.
  const jackson = 56.363 + 1.921 * 7 - 0.381 * 35 - 0.754 * (80 / 1.8 ** 2) + 10.987;
  assert.ok(Math.abs(estimateVo2Max({...profile, weeklyActiveMinutes: 210}) - jackson) < 1e-9);
  // With resting HR it averages in Uth: 15.3 × (208 − 0.7 × 35) / 60.
  const uth = 15.3 * (208 - 0.7 * 35) / 60;
  assert.ok(Math.abs(estimateVo2Max({...profile, weeklyActiveMinutes: 210, restingHr: 60}) - (jackson + uth) / 2) < 1e-9);
  const result = computePhysicalHealth({days: days(), profile, restingHr: 60});
  assert.equal(result.details.vo2Source, "estimate");
  assert.equal(result.parts.strength, null, "no in-app workouts: strength left out");
  assert.equal(estimateVo2Max({sex: "male", heightCm: 180, weightKg: 80}), null, "needs age");
});

test("unspecified sex averages the two norms and estimates", () => {
  assert.equal(vo2Median(35, "unspecified"), (41 + 35) / 2);
  assert.equal(vo2Median(72, "female"), 24);
});

test("sleep falls back to morning check-ins when nothing is tracked", () => {
  const result = computePhysicalHealth({
    days: days({sleepHours: null, bedtimeMin: null, checkInSleep: 75}), profile,
  });
  assert.equal(result.details.sleepSource, "checkIn");
  assert.equal(result.parts.sleep, 75);
});

test("short sleep and an irregular bedtime lower sleep habits", () => {
  const irregular = days().map((d, i) => ({...d, sleepHours: 6, bedtimeMin: (i % 2 ? 22 : 2) * 60}));
  const result = computePhysicalHealth({days: irregular, profile});
  assert.ok(result.parts.sleep < 60, String(result.parts.sleep));
});

test("before 14 days of data it's building, never guessed", () => {
  const sparse = days().map((d, i) => i < 10 ? d : {steps: null, exerciseMinutes: null, sleepHours: null, bedtimeMin: null, checkInSleep: null});
  const result = computePhysicalHealth({days: sparse, profile});
  assert.equal(result.score, null);
  assert.equal(result.label, "building");
  assert.equal(result.daysOfData, 10);
});

test("only the inputs it reads trigger a recalculation", () => {
  const base = {steps: {sum: 100}, heart_rate: {avg: 70}};
  assert.equal(physicalInputsChanged(base, {...base, heart_rate: {avg: 80}}), false);
  assert.equal(physicalInputsChanged(base, {...base, vo2_max: {avg: 42}}), true);
  assert.equal(physicalInputsChanged(base, {...base, morning_check_in: {sleep: 50}}), true);
});

test("it needs at least 3 of the 5 ingredients", () => {
  // Sleep and strength only (no steps, exercise or age): building.
  const result = computePhysicalHealth({
    days: days({steps: null, exerciseMinutes: null}), workouts: strength(6),
    logsWorkouts: true, profile: {},
  });
  assert.equal(result.score, null);
  assert.equal(result.parts.sleep, 100);
  assert.equal(result.parts.activeMinutes, null);
});
