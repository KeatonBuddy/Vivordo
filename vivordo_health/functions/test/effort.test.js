"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {hourlyLoads, computeEffort, effortInputsChanged} = require("../effort");

const MIN = 60000;
const dayStart = Date.UTC(2026, 9, 1, 6); // midnight in Edmonton (MDT)
const at = (h, m = 0) => dayStart + h * 60 * MIN + m * MIN;
const record = (events, priorities = [], wrapUpHour = 17) => ({
  dayStart, dayEnd: dayStart + 24 * 60 * MIN, wrapUpAt: at(wrapUpHour),
  events: events.map(([s, e, rating]) => ({start: at(...s), end: at(...e), rating, confidence: 0.85})),
  priorities,
});

// The busy Thursday from the design discussion, with the final rules.
const thursday = record([
  [[9], [10], 40], // planning
  [[10], [12], 55], // focus block, back-to-back
  [[14], [15], 75], // presentation
  [[15], [15, 30], 40], // debrief, back-to-back
  [[18], [19], 20], // dinner, after hours
], [{effort: "moderate", done: true}, {effort: "light", done: false}]);

test("the busy Thursday: 28.8 scheduled + 4 untimed, plus a 45-min run", () => {
  const effort = computeEffort({
    record: thursday,
    workouts: [{name: "Run", category: "Cardio", minutes: 45}],
    asOf: at(23),
  });
  // (2400 + 7350 + 4500 + 1537.5 + 1200 × 1.25) / 600 = 28.8; + 4 untimed.
  assert.equal(effort.mental, 32.8);
  assert.equal(effort.physical, 15.8, "45 min × 0.35");
  assert.equal(effort.total, 48.6);
  assert.equal(effort.backToBack, 2);
  assert.equal(effort.afterHoursMinutes, 60);
  assert.equal(effort.prioritiesDone, 1);
  assert.equal(effort.unfinishedPriorities, 1);
});

test("only what has happened counts", () => {
  const morning = computeEffort({record: thursday, asOf: at(10, 30)});
  // Planning (2400) + 30 min of the focus block: 1650 + bump 300 + ramp 37.5.
  assert.equal(morning.mental, round1((2400 + 1650 + 300 + 37.5) / 600 + 4));
  assert.equal(morning.busyMinutes, 90);
});

test("a priority ticked off early counts in its slot; unknown events count as 30", () => {
  const effort = computeEffort({
    record: record([[[9], [10], null]], [
      {start: at(20), end: at(21), effort: "demanding", done: true},
    ]),
    asOf: at(12),
  });
  // Unknown hour 30 × 60 = 1800; the 8 PM priority 75 × 60 × 1.25 = 5625.
  assert.equal(effort.mental, round1((1800 + 5625) / 600));
  assert.equal(effort.unknownMinutes, 60);
});

test("physical: workouts and Health minutes, else calories above usual; capped at 25", () => {
  const empty = record([]);
  const base = {record: empty, asOf: at(23)};
  assert.equal(computeEffort({...base, healthMinutes: 30}).physical, 6);
  assert.equal(computeEffort({...base, activeCalories: 900, usualCalories: 500}).physical, 8);
  assert.equal(computeEffort({...base, activeCalories: 300, usualCalories: 500}).physical, 0);
  assert.equal(computeEffort({...base, workouts: [{name: "HIIT", minutes: 120}]}).physical, 25);
  assert.equal(computeEffort({record: null, asOf: at(23)}), null, "no record, no Effort");
});

test("only exercise and calorie changes recalculate", () => {
  const base = {steps: {sum: 1}, exercise_time: {healthSum: 10}, active_calories: {sum: 300}};
  assert.equal(effortInputsChanged(base, {...base, steps: {sum: 5}}), false);
  assert.equal(effortInputsChanged(base, {...base, exercise_time: {healthSum: 20}}), true);
});

test("hourly loads match the phone's calculator (shared fixture)", () => {
  const fixture = JSON.parse(fs.readFileSync(
      path.join(__dirname, "../../test/fixtures/calendar_load_cases.json"), "utf8"));
  for (const c of fixture.cases) {
    const items = c.events.map(([s, e, rating], i) => ({id: `e${i}`, start: s * MIN, end: e * MIN, rating}));
    const loads = hourlyLoads(items, 0, c.hours * 60 * MIN, c.asOf * MIN)
        .slice(0, c.expected.length).map((h) => round1(h.load));
    assert.deepEqual(loads, c.expected, c.name);
  }
});

function round1(value) {
  return Math.round(value * 10) / 10;
}
