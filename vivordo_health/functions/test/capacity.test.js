"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {BIG_DAY_MIN, bigDayEffect, bigDayPenalty, bigDayScale, computeCapacity, capacityInputs, capacityInputsChanged, sleepNeed, clockGap, usualClockTime} = require("../capacity");

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
  // One body reading alone never decides the score.
  assert.equal(computeCapacity({history: history(), today: {restingHr: 55}}), null);
  assert.equal(computeCapacity({history: history(), today: {hrv: 60}}), null);
});

test("a check-in alone gives a provisional Capacity without the assumed body", () => {
  const result = computeCapacity({history: history(), today: {checkInFeel: 75, checkInSleep: 25}});
  assert.equal(result.provisional, true);
  assert.equal(result.parts.body, null, "neutral body left out");
  assert.equal(result.score, 50);
  // When sleep syncs, the neutral body comes back.
  const synced = computeCapacity({history: history(), today: {sleepHours: 7.5, checkInFeel: 75, checkInSleep: 25}});
  assert.equal(synced.parts.body, 70);
  assert.equal(synced.provisional, false);
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

test("only sleep, HRV, resting HR and check-in changes trigger a recalculation", () => {
  const base = {sleep: {avg: 7}, hrv: {avg: 50}, steps: {sum: 100}};
  assert.equal(capacityInputsChanged(base, {...base, steps: {sum: 900}}), false);
  assert.equal(capacityInputsChanged(base, {...base, hrv: {avg: 55}}), true);
  assert.equal(capacityInputsChanged(undefined, base), true);
  assert.equal(capacityInputsChanged(base, {...base, morning_check_in: {feel: 75}}), true);
  assert.equal(capacityInputs({morning_check_in: {feel: 75, sleep: 50}}).checkInSleep, 50);
  const bedtime = {toDate: () => new Date("2026-09-30T05:15:00Z")};
  assert.equal(capacityInputs({sleep: {avg: 7, bedtime}}).bedtimeMin, 5 * 60 + 15);
});

test("an implausible resting HR is left out, never a 0 from one bad reading", () => {
  // Sept 29 on a real account: no sleep, resting HR 67 against a normal of
  // 49 (neighbouring days 47–53). It used to score 0 and lock.
  const normal49 = history({restingHr: 49});
  assert.equal(computeCapacity({history: normal49, today: {restingHr: 67, hrv: 60}}), null,
      "bad resting HR dropped, HRV alone isn't enough");
  const withSleep = computeCapacity({history: normal49, today: {sleepHours: 7.5, restingHr: 67}});
  assert.equal(withSleep.restingHrIgnored, true);
  assert.equal(withSleep.parts.body, 70, "neutral, as with no body data");
  // Within 12 bpm still counts.
  const elevated = computeCapacity({history: normal49, today: {sleepHours: 7.5, restingHr: 56}});
  assert.equal(elevated.restingHrIgnored, false);
  assert.equal(elevated.parts.body, 28);
});

test("a big day costs Recovery by how far above the usual it was", () => {
  assert.equal(bigDayPenalty(1.9), 0);
  assert.equal(bigDayPenalty(2), 40);
  assert.equal(bigDayPenalty(2.5), 55);
  assert.equal(bigDayPenalty(3), 70);
  assert.equal(bigDayPenalty(4), 90);
  assert.equal(bigDayPenalty(9), 90);
});

test("the strongest of the last 3 days counts, fading over them", () => {
  // Usual 20 a day: 60 yesterday is 3× → 70; 80 two days ago is 4× → 90 × ½.
  assert.deepEqual(bigDayEffect([60, null, null], 20), {daysAgo: 1, ratio: 3, penalty: 70});
  assert.deepEqual(bigDayEffect([20, 80, null], 20), {daysAgo: 2, ratio: 4, penalty: 45});
  assert.deepEqual(bigDayEffect([20, 20, 80], 20), {daysAgo: 3, ratio: 4, penalty: 22.5});
  // A normal week, or no usual yet: nothing.
  assert.equal(bigDayEffect([30, 25, 20], 20), null);
  assert.equal(bigDayEffect([80, null, null], null), null);
  // Rarely exercises (usual 2): an hour (12 points) is 2× of the 6-point
  // floor, not 6×; under 12 points is never a big day.
  assert.deepEqual(bigDayEffect([12, null, null], 2), {daysAgo: 1, ratio: 2, penalty: 40});
  assert.equal(bigDayEffect([10, null, null], 2), null);
});

test("a big day lowers Capacity, less when the body has recovered", () => {
  const base = {sleepHours: 7.5, bedtimeMin: 23 * 60, yesterdayEffort: 40, usualEffort: 40};
  const bigDay = {day: "2026-10-06", ratio: 3, penalty: 70};
  const calm = computeCapacity({history: history(), today: {...base, hrv: 60, restingHr: 55}});
  // Body at its normal (70): recovered, so half of 70.
  const recovered = computeCapacity({history: history(), today: {...base, hrv: 60, restingHr: 55, bigDay}});
  assert.equal(recovered.parts.recovery, 65);
  assert.deepEqual(recovered.bigDay, {day: "2026-10-06", ratio: 3, penalty: 35, halved: true, kind: "minutes"});
  // Body strained (HRV down, resting HR up): the full 70.
  const strained = computeCapacity({history: history(), today: {...base, hrv: 51, restingHr: 59, bigDay}});
  assert.equal(strained.parts.recovery, 30);
  assert.equal(strained.bigDay.halved, false);
  assert.ok(recovered.score < calm.score, `${recovered.score} < ${calm.score}`);
  // Yesterday's Effort and the big day are the same day: the larger counts.
  const both = computeCapacity({history: history(), today: {...base, hrv: 51, restingHr: 59, yesterdayEffort: 120, bigDay}});
  assert.equal(both.parts.recovery, 20, "Effort 80 over the usual beats 70");
  // With no Effort history the big day still sets Recovery.
  const activityUsual = {kind: "minutes", usual: 20, base: 20, threshold: 40};
  const noEffort = computeCapacity({history: history(), today: {sleepHours: 7.5, bedtimeMin: 23 * 60, hrv: 51, restingHr: 59, bigDay, activityUsual}});
  assert.equal(noEffort.parts.recovery, 30);
  assert.deepEqual(noEffort.activityUsual, activityUsual);
});

test("heart-rate load has its own minimum, and the app gets the threshold", () => {
  // TRIMP: a usual of 30 counts as at least 20; big from 60.
  assert.deepEqual(bigDayScale(30, BIG_DAY_MIN.heart), {base: 30, threshold: 60});
  assert.deepEqual(bigDayScale(10, BIG_DAY_MIN.heart), {base: 20, threshold: 40});
  assert.deepEqual(bigDayScale(8, BIG_DAY_MIN.minutes), {base: 8, threshold: 16});
  assert.equal(bigDayEffect([35, null, null], 10, BIG_DAY_MIN.heart), null, "under 40");
  assert.deepEqual(bigDayEffect([60, null, null], 20, BIG_DAY_MIN.heart), {daysAgo: 1, ratio: 3, penalty: 70});
});
