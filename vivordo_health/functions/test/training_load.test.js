"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {trainingLoadFor, relativeDay} = require("../training_load");

const DAY = "2026-10-08";
const key = (k) => new Date(Date.parse(`${DAY}T00:00:00Z`) - k * 86400000).toISOString().slice(0, 10);
// 35 days of minutes load: [usual] on days 8–35 (base 10, so each is 1.0×
// an ordinary active day) and [week] for days 7..1 (oldest first).
function loads(week, {usual = 10, heart = null} = {}) {
  const minutesOn = new Map();
  for (let k = 8; k <= 35; k++) minutesOn.set(key(k), usual);
  week.forEach((v, i) => minutesOn.set(key(7 - i), v));
  return {minutesOn, minutesBase: 10, heartOn: heart ?? new Map(), heartBase: heart ? 50 : null};
}
const normalBody = [{hrv: 50, restingHr: 55}, {hrv: 50, restingHr: 55}, {hrv: 50, restingHr: 55}];
const offBody = [{hrv: 44, restingHr: 59}, {hrv: 50, restingHr: 59}, {hrv: 50, restingHr: 55}];
const run = (week, extra = {}) => trainingLoadFor({day: DAY, loads: loads(week, extra), mornings: normalBody, hrvNormal: 50, restingHrNormal: 55, ...extra});

test("a usual week is Steady; ratio is this week ÷ the usual week", () => {
  const r = run([10, 10, 10, 10, 10, 10, 10]);
  assert.equal(r.state, "steady");
  assert.equal(r.ratio, 1);
  assert.equal(r.usualWeek, 7);
  assert.equal(r.days.length, 7);
  assert.equal(r.days[0].day, key(7));
  assert.equal(r.kind, "minutes");
});

test("lighter, building, high and strained", () => {
  assert.equal(run([5, 5, 5, 5, 5, 5, 0]).state, "lighter");
  // 1.4×: building (High needs 1.5× and 3 hard days).
  assert.equal(run([20, 20, 10, 10, 10, 10, 18]).state, "building");
  // 1.6× (11.2 ordinary days against 7) with 6 hard days, body fine: high.
  const high = run([20, 15, 15, 10, 15, 15, 22]);
  assert.equal(high.ratio, 1.6);
  assert.equal(high.hardDays, 6);
  assert.equal(high.state, "high");
  // The same week with HRV down / resting HR up on 2 of 3 mornings.
  const strained = trainingLoadFor({day: DAY, loads: loads([20, 15, 15, 10, 15, 15, 22]), mornings: offBody, hrvNormal: 50, restingHrNormal: 55});
  assert.equal(strained.state, "strained");
  assert.deepEqual(strained.body, {mornings: 3, hrvLow: 1, restingHigh: 2, restingHrChange: 4, agrees: true});
  // One huge day is a peak, not a pattern: never High on its own.
  assert.notEqual(run([0, 0, 0, 0, 0, 0, 80]).state, "high");
});

test("High holds until this week drops under 1.3×", () => {
  const week = [15, 14, 14, 10, 10, 10, 18]; // exactly 1.3×
  assert.equal(run(week).state, "building");
  assert.equal(run(week, {previousState: "high"}).state, "high");
  assert.equal(run([10, 10, 10, 10, 10, 10, 10], {previousState: "strained"}).state, "steady");
});

test("a measured day uses heart rate, a watch-off day minutes", () => {
  const heart = new Map([[key(1), 150]]);
  assert.deepEqual(relativeDay(key(1), loads([10, 10, 10, 10, 10, 10, 20], {heart})), {value: 3, kind: "heart"});
  assert.deepEqual(relativeDay(key(2), loads([10, 10, 10, 10, 10, 10, 20], {heart})), {value: 1, kind: "minutes"});
  assert.equal(run([10, 10, 10, 10, 10, 10, 20], {heart}).kind, "mixed");
});

test("too little history, or almost no usual activity, is learning", () => {
  const sparse = {minutesOn: new Map([[key(9), 10], [key(1), 30]]), minutesBase: 10};
  assert.deepEqual(trainingLoadFor({day: DAY, loads: sparse}), {version: 1, state: "learning", coveredDays: 1});
  assert.equal(run([0, 0, 0, 0, 0, 0, 0], {usual: 1}).state, "learning");
});
