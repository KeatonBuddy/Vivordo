"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {dueWhoopEndpoints} = require("../whoop_schedule");

const morning = Date.parse("2026-08-19T15:00:00.000Z");
const edmontonOffset = -6 * 60;

test("first morning use requests sleep", () => {
  assert.deepEqual(dueWhoopEndpoints({
    nowMs: morning,
    timezoneOffsetMinutes: edmontonOffset,
  }), {
    sleep: true,
    localDate: "2026-08-19",
    sleepSlot: "morning",
  });
});

test("automatic sleep does not run before 4 a.m. local time", () => {
  const overnight = Date.parse("2026-08-19T09:59:00.000Z");
  assert.deepEqual(dueWhoopEndpoints({
    nowMs: overnight,
    timezoneOffsetMinutes: edmontonOffset,
  }), {
    sleep: false,
    localDate: "2026-08-19",
    sleepSlot: "overnight",
  });
});

test("morning sleep runs only once", () => {
  const notDue = dueWhoopEndpoints({
    nowMs: morning,
    timezoneOffsetMinutes: edmontonOffset,
    lastSleepMorningDate: "2026-08-19",
  });
  assert.equal(notDue.sleep, false);
});

test("midday is a second independent sleep safety slot", () => {
  const midday = Date.parse("2026-08-19T19:00:00.000Z");
  const due = dueWhoopEndpoints({
    nowMs: midday,
    timezoneOffsetMinutes: edmontonOffset,
    lastSleepMorningDate: "2026-08-19",
  });
  assert.equal(due.sleepSlot, "midday");
  assert.equal(due.sleep, true);

  const complete = dueWhoopEndpoints({
    nowMs: midday,
    timezoneOffsetMinutes: edmontonOffset,
    lastSleepMorningDate: "2026-08-19",
    lastSleepMiddayDate: "2026-08-19",
  });
  assert.equal(complete.sleep, false);
});

test("manual force requests sleep regardless of timestamps", () => {
  const due = dueWhoopEndpoints({
    nowMs: morning,
    timezoneOffsetMinutes: edmontonOffset,
    force: true,
    lastSleepMorningDate: "2026-08-19",
  });
  assert.equal(due.sleep, true);
});

test("manual force still works overnight", () => {
  const overnight = Date.parse("2026-08-19T09:00:00.000Z");
  const due = dueWhoopEndpoints({
    nowMs: overnight,
    timezoneOffsetMinutes: edmontonOffset,
    force: true,
  });
  assert.equal(due.sleepSlot, "overnight");
  assert.equal(due.sleep, true);
});
