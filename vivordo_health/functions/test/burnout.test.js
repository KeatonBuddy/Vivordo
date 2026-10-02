"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {evaluateRange, scoreSignal, SIGNALS, dayKey, dayIndex, dailySignals, warningBody} = require("../burnout");

const END = "2026-09-30";
const end = dayIndex(END);

// Deterministic noise so every run sees the same "random" days.
function noise(seed) {
  let s = seed;
  return () => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648 - 0.5;
  };
}

// A normal person: Capacity ~80, Effort ~35, mood ~70, sleep ~7h, resting
// HR ~55, 2 back-to-backs and 20 after-hours minutes a day. `shape(daysAgo)`
// returns overrides per day; `skip(key, daysAgo)` drops a signal.
function history({days = 84, shape = () => ({}), seed = 7, skip = () => false} = {}) {
  const r = noise(seed);
  const out = [];
  for (let ago = days - 1; ago >= 0; ago--) {
    const o = shape(ago);
    const capacity = {
      score: Math.round((o.capacity ?? 80) + r() * 10), provisional: false,
      sleepHours: (o.sleep ?? 7) + r() * 0.8, restingHr: (o.rhr ?? 55) + r() * 3,
      hrv: 60 + r() * 6, hrvKind: "sdnn",
    };
    const effort = {
      total: (o.effort ?? 35) + r() * 10, version: 1,
      backToBack: Math.max(0, Math.round((o.b2b ?? 2) + r() * 2)),
      afterHoursMinutes: Math.max(0, (o.afterHours ?? 20) + r() * 20),
    };
    const scores = {};
    if (!skip("capacity", ago)) scores.capacity = capacity;
    if (!skip("effort", ago)) scores.effort = effort;
    const metrics = skip("mood", ago) ? {} : {mood: {avg: (o.mood ?? 70) + r() * 12}};
    out.push({day: dayKey(end - ago), scores, metrics});
  }
  return out;
}

const levels = (results) => results.map((r) => r.level);

test("a steady person stays steady", () => {
  const results = evaluateRange(history(), dayKey(end - 13), END);
  assert.deepEqual([...new Set(levels(results))], ["steady"]);
});

test("a slide in Capacity and Effort goes watch, then warning, with drivers", () => {
  // Over the last 3 weeks Capacity falls 20 and Effort rises 15, with sleep
  // shorter and more back-to-backs.
  const ramp = (ago, size) => ago < 21 ? size * (21 - ago) / 21 : 0;
  const days = history({shape: (ago) => ({
    capacity: 80 - ramp(ago, 20), effort: 35 + ramp(ago, 15),
    sleep: 7 - ramp(ago, 1), b2b: 2 + ramp(ago, 3),
  })});
  const results = evaluateRange(days, dayKey(end - 27), END);
  const seen = levels(results);
  assert.equal(seen[0], "steady", "quiet before the ramp starts");
  assert.ok(seen.indexOf("watch") > 0 && seen.indexOf("watch") < seen.indexOf("warning"), seen.join(","));
  const last = results.at(-1);
  assert.equal(last.level, "warning");
  assert.ok(last.areas.capacity.elevated && last.areas.effort.elevated);
  assert.equal(last.areas.mood.elevated, false, "mood held steady");
  const drivers = last.drivers.map((d) => d.name);
  assert.ok(drivers.includes("sleepHours") && drivers.includes("backToBack"), drivers.join(","));
  assert.equal(results.filter((r) => r.notify).length, 1, "notified once");
  const firstWarning = results.find((r) => r.level === "warning");
  assert.equal(last.since, firstWarning.day, "dated from when the warning started");
});

test("heavier days alone are watch, never a warning", () => {
  const days = history({days: 100, shape: (ago) => ago < 35 ? {effort: 50, afterHours: 70} : {}});
  const results = evaluateRange(days, dayKey(end - 20), END);
  assert.equal(results.at(-1).level, "watch");
  assert.ok(!levels(results).includes("warning"));
  assert.equal(results.filter((r) => r.notify).length, 0, "watch never notifies");
});

test("a milder shift in two areas shows watch for about a week before warning", () => {
  const days = history({days: 100, shape: (ago) => ago < 35 ? {capacity: 72, mood: 63} : {}});
  const seen = levels(evaluateRange(days, dayKey(end - 41), END));
  const watch = seen.indexOf("watch");
  const warning = seen.indexOf("warning");
  assert.ok(watch > 0 && warning - watch >= 5, seen.join(","));
  assert.equal(seen.at(-1), "warning");
});

test("one bad weekend does not raise anything", () => {
  const days = history({shape: (ago) => ago === 3 || ago === 4 ? {capacity: 40, effort: 70, mood: 30} : {}});
  assert.deepEqual([...new Set(levels(evaluateRange(days, dayKey(end - 13), END)))], ["steady"]);
});

test("a warning holds through a calm week, then clears without flickering", () => {
  const strained = (ago) => ago >= 35 && ago < 70;
  const days = history({days: 140, shape: (ago) => strained(ago) ? {capacity: 62, effort: 52} : {}});
  const results = evaluateRange(days, dayKey(end - 60), END);
  const seen = levels(results);
  const first = seen.indexOf("warning");
  const last = seen.lastIndexOf("warning");
  assert.ok(first >= 0, seen.join(","));
  assert.ok(seen.slice(first, last + 1).every((l) => l === "warning"), seen.join(","));
  assert.equal(seen.at(-1), "steady");
  assert.equal(results.filter((r) => r.notify).length, 1, "notified once");
});

test("a new user is learning, with days counted towards the first check", () => {
  const [night] = evaluateRange(history({days: 20}), END, END);
  assert.equal(night.level, "learning");
  assert.equal(night.learningDays, 20);
});

test("before Effort exists, Capacity and Mood still work", () => {
  const days = history({skip: (key) => key === "effort", shape: (ago) => ago < 21 ? {capacity: 62, mood: 52} : {}});
  assert.equal(evaluateRange(days, END, END)[0].level, "warning");
  const capacityOnly = history({skip: (key) => key !== "capacity", shape: (ago) => ago < 21 ? {capacity: 62} : {}});
  assert.equal(evaluateRange(capacityOnly, END, END)[0].level, "watch", "one area can reach watch");
});

test("provisional Capacity, ignored resting HR and other Effort versions are left out", () => {
  const signals = dailySignals({
    capacity: {score: 40, provisional: true},
    effort: {total: 30, version: 99},
  }, {mood: {avg: 60}});
  assert.equal(signals.capacity, null);
  assert.equal(signals.effort, null);
  assert.equal(signals.mood, 60);
  const ignored = dailySignals({capacity: {score: 70, provisional: false, restingHr: 67, restingHrIgnored: true, hrv: 50, hrvKind: "sdnn"}});
  assert.equal(ignored.restingHeartRate, null);
  assert.deepEqual(ignored.hrv, {sdnn: 50});
});

test("small shifts under the minimum meaningful change score zero", () => {
  const baseline = Array.from({length: 30}, (_, i) => 80 + (i % 3) - 1);
  const recent = Array.from({length: 14}, () => 77);
  assert.equal(scoreSignal(SIGNALS.capacity, recent, baseline).score, 0);
  assert.equal(scoreSignal(SIGNALS.capacity, recent.slice(0, 5), baseline), null, "too few recent days");
});

test("the push names the areas that drifted", () => {
  assert.equal(warningBody({capacity: {elevated: true}, mood: {elevated: true}}),
      "Lower energy and lower mood than usual. Take a look at what's changed.");
});
