"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {minuteReadings, maxHeartRate, heartRateLoad, computeActivityLoad, heartRateChanged} = require("../activity_load");

const T0 = Date.parse("2026-10-06T06:00:00Z");
const at = (minute, bpm) => ({timestamp: new Date(T0 + minute * 60000).toISOString(), bpm});
// A day: a reading every 5 minutes at 60 bpm for 16 h, and a workout of
// [minutes] at [bpm] sampled every minute from 10:00.
function day({workoutMinutes = 0, workoutBpm = 150, source = "apple_health"} = {}) {
  const entries = [];
  for (let m = 0; m < 16 * 60; m += 5) {
    if (m >= 240 && m < 240 + workoutMinutes) continue;
    entries.push(at(m, 60));
  }
  for (let m = 0; m < workoutMinutes; m++) entries.push(at(240 + m, workoutBpm));
  entries.sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  return {heart_rate_sources: {[source]: {entries}}, resting_heart_rate: {avg: 55}};
}
const person = {age: 30, sex: "male"};

test("everyday heart rate adds nothing; exercise minutes add load", () => {
  assert.equal(computeActivityLoad(day(), person).trimp, 0);
  const hour = computeActivityLoad(day({workoutMinutes: 60}), person);
  // Max 187 (Tanaka at 30), rest 55: 150 bpm is 72% of reserve.
  assert.equal(hour.maxHr, 187);
  assert.equal(hour.minutes, 60);
  assert.ok(hour.trimp > 100 && hour.trimp < 130, String(hour.trimp));
  // Harder counts for more than longer-but-easy.
  const hard45 = computeActivityLoad(day({workoutMinutes: 45, workoutBpm: 165}), person).trimp;
  const easy90 = computeActivityLoad(day({workoutMinutes: 90, workoutBpm: 120}), person).trimp;
  assert.ok(hard45 > easy90, `${hard45} > ${easy90}`);
});

test("sparse readings each stand for up to 5 minutes", () => {
  const readings = [0, 5, 10, 30].map((m) => ({t: T0 + m * 60000, bpm: 150}));
  const load = heartRateLoad(readings, {restingHr: 55, maxHr: 187, sex: "male"});
  // 5 + 5 + 5 (capped gap) + 1 (last).
  assert.equal(load.minutes, 16);
});

test("a watch not worn gives no load; a wearable wins a shared minute", () => {
  assert.equal(computeActivityLoad({heart_rate_sources: {apple_health: {entries: [at(0, 150)]}}}, person), null);
  const both = {heart_rate_sources: {apple_health: {entries: [at(0, 80)]}, whoop_ble: {entries: [at(0, 140)]}}};
  assert.deepEqual(minuteReadings(both).map((r) => r.bpm), [140]);
});

test("max heart rate: Tanaka, or 190, raised to what was seen", () => {
  assert.equal(maxHeartRate(30, 170), 187);
  assert.equal(maxHeartRate(null, 170), 190);
  assert.equal(maxHeartRate(30, 199), 199);
  assert.equal(maxHeartRate(30, 260), 220);
});

test("only heart-rate changes trigger a recalculation", () => {
  const base = day({workoutMinutes: 30});
  assert.equal(heartRateChanged(base, {...base, steps: {sum: 100}}), false);
  assert.equal(heartRateChanged(base, day({workoutMinutes: 40})), true);
  assert.equal(heartRateChanged(base, {...base, resting_heart_rate: {avg: 58}}), true);
});
