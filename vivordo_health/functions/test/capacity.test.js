"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {computeCapacity, capacityInputs, capacityInputsChanged, sleepNeed, clockGap, usualClockTime} = require("../capacity");

// 30 normal days: 7.5 h sleep, bed at 23:00, HRV 60, resting HR 55.
const history = (overrides = {}) => Array.from({length: 30}, () => ({
  sleepHours: 7.5, bedtimeMin: 23 * 60, hrv: 60, restingHr: 55, ...overrides,
}));

test("a normal day matches the doc's worked example (89, high)", () => {
  const result = computeCapacity({history: history(), today: {
    sleepHours: 7.4, bedtimeMin: 23 * 60 + 10, hrv: 60, restingHr: 55,
    yesterdayEffort: 40, usualEffort: 40,
  }});
  assert.equal(result.score, 89);
  assert.equal(result.label, "high");
  assert.equal(result.sleepNeed, 7.5);
  assert.equal(result.provisional, false);
});

test("a rough day matches the doc's worked example (61, moderate)", () => {
  const today = {
    sleepHours: 5.5, bedtimeMin: 30, // 00:30, 90 min after the usual 23:00
    hrv: 51, restingHr: 59, // HRV 15% below normal, resting HR +4
    yesterdayEffort: 65, usualEffort: 40,
  };
  const result = computeCapacity({history: history(), today});
  assert.equal(result.bedtimeOffsetMin, 90);
  assert.deepEqual(result.parts, {sleep: 63.3, body: 50.5, recovery: 75, checkIn: null});
  assert.equal(result.score, 61);
  assert.equal(result.label, "moderate");
  // A morning check-in (feel 40, slept "Poor" = 25) is added when answered.
  const withCheckIn = computeCapacity({history: history(), today: {...today, checkInFeel: 40, checkInSleep: 25}});
  assert.equal(withCheckIn.score, 57);
});

test("missing body data counts as a neutral 70, not left out", () => {
  const today = {sleepHours: 7.4, bedtimeMin: 23 * 60, yesterdayEffort: 40, usualEffort: 40};
  const result = computeCapacity({history: history({hrv: null, restingHr: null}), today});
  assert.equal(result.score, 89, "same as the normal day with a wearable");
  assert.equal(result.bodyMeasured, false);
  assert.equal(result.parts.body, 70);
});

test("no sleep and no measured body is unavailable, never guessed", () => {
  assert.equal(computeCapacity({history: history(), today: {}}), null);
  const bodyOnly = computeCapacity({history: history(), today: {hrv: 60, restingHr: 55}});
  assert.equal(bodyOnly.provisional, true, "waiting for last night's sleep");
});

test("ingredients that don't exist yet are left out and re-weighted", () => {
  // Effort isn't built yet: Capacity uses sleep 45 and body 35 only.
  const result = computeCapacity({history: history(), today: {sleepHours: 7.5, hrv: 60, restingHr: 55}});
  assert.equal(result.parts.recovery, null);
  assert.equal(result.score, Math.round((45 * 100 + 35 * 70) / 80));
});

test("sleep: own need between 7 and 9 h, 8 h until 14 nights, penalty under 5 h", () => {
  assert.equal(sleepNeed([]), 8);
  assert.equal(sleepNeed(Array(14).fill(6)), 7);
  assert.equal(sleepNeed(Array(14).fill(9.5)), 9);
  const short = computeCapacity({history: history(), today: {sleepHours: 4.5}});
  assert.equal(short.parts.sleep, Math.round(100 * (4.5 / 7.5) * 0.7 * 10) / 10);
});

test("bedtimes are compared around midnight", () => {
  assert.equal(clockGap(23 * 60 + 30, 15), 45);
  assert.equal(Math.round(usualClockTime([23 * 60 + 30, 30])), 0);
  const late = computeCapacity({history: history(), today: {sleepHours: 7.5, bedtimeMin: 15}});
  assert.equal(late.bedtimeOffsetMin, 75);
  assert.equal(late.parts.sleep, 90);
  const ok = computeCapacity({history: history(), today: {sleepHours: 7.5, bedtimeMin: 23 * 60 + 45}});
  assert.equal(ok.parts.sleep, 100);
});

test("only sleep, HRV and resting HR changes trigger a recalculation", () => {
  const base = {sleep: {avg: 7}, hrv: {avg: 50}, steps: {sum: 100}};
  assert.equal(capacityInputsChanged(base, {...base, steps: {sum: 900}}), false);
  assert.equal(capacityInputsChanged(base, {...base, hrv: {avg: 55}}), true);
  assert.equal(capacityInputsChanged(undefined, base), true);
  const bedtime = {toDate: () => new Date("2026-09-30T05:15:00Z")};
  assert.equal(capacityInputs({sleep: {avg: 7, bedtime}}).bedtimeMin, 5 * 60 + 15);
});
