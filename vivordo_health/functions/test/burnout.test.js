"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {evaluateRange, scoreSignal, SIGNALS, dayKey, dayIndex} = require("../burnout");

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

// A normal person: stress ~48, mood ~70, sleep ~7h, resting HR ~58,
// ~30 exercise minutes. `shape(daysAgo)` returns overrides per day.
function history({days = 84, shape = () => ({}), seed = 7, skip = () => false} = {}) {
  const r = noise(seed);
  const out = [];
  for (let ago = days - 1; ago >= 0; ago--) {
    const o = shape(ago);
    const data = {
      stress: {avg: (o.stress ?? 48) + r() * 8},
      mood: {avg: (o.mood ?? 70) + r() * 12},
      sleep: {avg: (o.sleep ?? 7) + r() * 0.8},
      resting_heart_rate: {avg: (o.rhr ?? 58) + r() * 3},
      exercise_time: {sum: Math.max(0, (o.exercise ?? 30) + r() * 20)},
    };
    for (const key of Object.keys(data)) if (skip(key, ago)) delete data[key];
    out.push({day: dayKey(end - ago), data});
  }
  return out;
}

const levels = (results) => results.map((r) => r.level);

test("a steady person stays steady", () => {
  const results = evaluateRange(history(), dayKey(end - 13), END);
  assert.deepEqual([...new Set(levels(results))], ["steady"]);
});

test("a gradual build-up moves to watch, then warning, with reasons", () => {
  // Over the last 3 weeks stress creeps up 15 points and mood slides 18.
  const ramp = (ago, size) => ago < 21 ? size * (21 - ago) / 21 : 0;
  const days = history({shape: (ago) => ({stress: 48 + ramp(ago, 15), mood: 70 - ramp(ago, 18)})});
  const results = evaluateRange(days, dayKey(end - 27), END);
  const seen = levels(results);
  assert.equal(seen[0], "steady", "quiet before the ramp starts");
  assert.ok(seen.indexOf("watch") > 0 && seen.indexOf("watch") < seen.indexOf("warning"), seen.join(","));
  const last = results.at(-1);
  assert.equal(last.level, "warning");
  assert.ok(last.reasons.some((r) => r.startsWith("Stress")), last.reasons.join(" | "));
  assert.ok(last.reasons.some((r) => r.startsWith("Mood")), last.reasons.join(" | "));
});

test("a milder, steady shift shows watch for about a week before warning", () => {
  const days = history({days: 100, shape: (ago) => ago < 35 ? {stress: 53, mood: 63} : {}});
  const seen = levels(evaluateRange(days, dayKey(end - 41), END));
  const watch = seen.indexOf("watch");
  const warning = seen.indexOf("warning");
  assert.ok(watch > 0 && warning - watch >= 5, seen.join(","));
  assert.equal(seen.at(-1), "warning");
});

test("one bad weekend does not raise anything", () => {
  const days = history({shape: (ago) => ago === 3 || ago === 4 ? {stress: 75, mood: 30, sleep: 5} : {}});
  const results = evaluateRange(days, dayKey(end - 13), END);
  assert.deepEqual([...new Set(levels(results))], ["steady"]);
});

test("a warning holds through a calm week, then clears without flickering", () => {
  // Strain from 70 to 35 days ago, then back to normal.
  const strained = (ago) => ago >= 35 && ago < 70;
  const days = history({days: 140, shape: (ago) => strained(ago) ? {stress: 64, mood: 52} : {}});
  const results = evaluateRange(days, dayKey(end - 60), END);
  const seen = levels(results);
  const firstWarning = seen.indexOf("warning");
  const lastWarning = seen.lastIndexOf("warning");
  assert.ok(firstWarning >= 0, seen.join(","));
  // Once it starts, it stays a warning until it clears for good.
  assert.ok(seen.slice(firstWarning, lastWarning + 1).every((l) => l === "warning"), seen.join(","));
  assert.equal(seen.at(-1), "steady");
  assert.equal(results.filter((r) => r.notify).length, 1, "notified once");
});

test("patchy data uses what it has: no HRV, sleep on few days", () => {
  const ramp = (ago) => ago < 21 ? (21 - ago) / 21 : 0;
  const days = history({
    shape: (ago) => ({stress: 48 + 15 * ramp(ago), mood: 70 - 18 * ramp(ago)}),
    skip: (key, ago) => key === "sleep" && ago % 5 !== 0,
  });
  assert.equal(evaluateRange(days, END, END)[0].level, "warning");
});

test("a new user is still learning", () => {
  const results = evaluateRange(history({days: 20}), END, END);
  assert.equal(results[0].level, "learning");
});

test("without mood check-ins there is only one group, so it keeps learning", () => {
  // Phase 1 limitation: calendar load (Phase 2) will add a second group.
  const days = history({skip: (key) => key === "mood", shape: (ago) => ago < 21 ? {stress: 66} : {}});
  assert.equal(evaluateRange(days, END, END)[0].level, "learning");
});

test("small shifts under the minimum meaningful change score zero", () => {
  const baseline = Array.from({length: 30}, (_, i) => 48 + (i % 3) - 1);
  const recent = Array.from({length: 14}, () => 50);
  assert.equal(scoreSignal(SIGNALS.stress, recent, baseline).score, 0);
  assert.equal(scoreSignal(SIGNALS.stress, recent.slice(0, 5), baseline), null, "too few recent days");
});

test("HRV is judged on a relative change and falls are worse", () => {
  const baseline = Array.from({length: 30}, (_, i) => 60 + (i % 5) - 2);
  const drop = scoreSignal(SIGNALS.hrv, Array(14).fill(48), baseline);
  const rise = scoreSignal(SIGNALS.hrv, Array(14).fill(72), baseline);
  assert.ok(drop.elevated && drop.score > 2, JSON.stringify(drop));
  assert.equal(rise.score, 0);
});
