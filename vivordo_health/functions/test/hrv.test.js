"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {hrvReadings, pickHrv} = require("../hrv");
const {assess, dailySignals, dayKey, dayIndex} = require("../burnout");

const apple = (avg) => ({hrv: {avg, source: "apple_health"}});
const whoop = (avg) => ({hrv_rmssd: {avg, source: "whoop", method: "rmssd"}});

test("readings are keyed by kind and ignore unknown or invalid values", () => {
  assert.deepEqual(hrvReadings({...apple(61), ...whoop(44)}), {"rmssd:whoop": 44, "sdnn": 61});
  assert.deepEqual(hrvReadings({hrv_rmssd: {avg: 40, source: "garmin"}, hrv: {avg: 0}}), {});
  assert.deepEqual(hrvReadings(undefined), {});
});

test("uses the wearable once it has a normal, never mixing kinds", () => {
  const history = Array.from({length: 7}, () => hrvReadings({...apple(60), ...whoop(45)}));
  const pick = pickHrv(hrvReadings({...apple(58), ...whoop(40)}), history, 7);
  assert.equal(pick.kind, "rmssd:whoop");
  assert.equal(pick.value, 40);
  assert.deepEqual(pick.history, Array(7).fill(45));
});

test("keeps Apple SDNN while a new wearable builds its normal", () => {
  const history = [
    ...Array.from({length: 10}, () => hrvReadings(apple(60))),
    ...Array.from({length: 3}, () => hrvReadings({...apple(60), ...whoop(45)})),
  ];
  const pick = pickHrv(hrvReadings({...apple(57), ...whoop(42)}), history, 7);
  assert.equal(pick.kind, "sdnn");
  assert.equal(pick.value, 57);
});

test("a wearable-only user without a normal yet still reports its kind", () => {
  const pick = pickHrv(hrvReadings(whoop(42)), [hrvReadings(whoop(45))], 7);
  assert.deepEqual(pick, {kind: "rmssd:whoop", value: 42, history: [45]});
  assert.deepEqual(pickHrv({}, [{}], 7), {kind: null, value: null, history: [null]});
});

test("burnout compares HRV within one kind", () => {
  // Burnout reads HRV from each day's Capacity, which carries one kind.
  // Apple SDNN ~60 for 10 weeks, then a WHOOP is connected and Capacity
  // switches to its RMSSD (~40, a lower number by nature) for the last 2
  // weeks. Mixing kinds would read a big drop.
  const end = dayIndex("2026-09-30");
  const capacity = (hrv, hrvKind) => ({capacity: {score: 80, provisional: false, hrv, hrvKind}});
  const byDay = new Map();
  for (let ago = 83; ago >= 0; ago--) {
    byDay.set(dayKey(end - ago), dailySignals(ago < 14 ?
      capacity(40, "rmssd:whoop") : capacity(60 + (ago % 3), "sdnn")));
  }
  const {signals} = assess(byDay, "2026-09-30");
  assert.equal(signals.hrv, undefined, "neither kind has both a normal and a recent run");
  assert.equal(signals.capacity.elevated, false);
});
