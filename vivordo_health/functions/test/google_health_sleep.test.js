"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  normalizeGoogleHealthSleep,
  sleepDayKey,
  sleepMinutes,
} = require("../google_health_sleep");

const stage = (type, startTime, endTime) => ({type, startTime, endTime});

test("normalizes Fitbit stages, times, duration, and efficiency", () => {
  const result = normalizeGoogleHealthSleep([{
    sleep: {
      interval: {
        startTime: "2026-08-19T05:00:00Z",
        endTime: "2026-08-19T13:00:00Z",
        endUtcOffset: "-21600s",
      },
      type: "STAGES",
      summary: {
        minutesInSleepPeriod: "480",
        minutesAsleep: "420",
        stagesSummary: [
          {type: "AWAKE", minutes: "60"},
          {type: "LIGHT", minutes: "210"},
          {type: "DEEP", minutes: "90"},
          {type: "REM", minutes: "120"},
        ],
      },
    },
  }]);

  assert.deepEqual(result["2026-08-19"].stages, {
    awake: 60,
    core: 210,
    deep: 90,
    rem: 120,
  });
  assert.equal(result["2026-08-19"].minutes, 420);
  assert.equal(result["2026-08-19"].efficiency, 87.5);
  assert.equal(
      result["2026-08-19"].bedtime.toISOString(),
      "2026-08-19T05:00:00.000Z",
  );
  assert.equal(
      result["2026-08-19"].wakeTime.toISOString(),
      "2026-08-19T13:00:00.000Z",
  );
});

test(
    "falls back to stage intervals and combines sleeps on one wake day",
    () => {
      const result = normalizeGoogleHealthSleep([
        {
          sleep: {
            interval: {
              startTime: "2026-08-19T06:00:00Z",
              endTime: "2026-08-19T12:00:00Z",
              civilEndTime: {date: {year: 2026, month: 8, day: 19}},
            },
            type: "STAGES",
            stages: [
              stage("LIGHT", "2026-08-19T06:00:00Z", "2026-08-19T09:00:00Z"),
              stage("DEEP", "2026-08-19T09:00:00Z", "2026-08-19T10:00:00Z"),
              stage("REM", "2026-08-19T10:00:00Z", "2026-08-19T12:00:00Z"),
            ],
          },
        },
        {
          sleep: {
            interval: {
              startTime: "2026-08-19T18:00:00Z",
              endTime: "2026-08-19T19:00:00Z",
              civilEndTime: {date: {year: 2026, month: 8, day: 19}},
            },
            type: "STAGES",
            stages: [
              stage("LIGHT", "2026-08-19T18:00:00Z", "2026-08-19T19:00:00Z"),
            ],
          },
        },
      ]);

      assert.equal(result["2026-08-19"].minutes, 420);
      assert.deepEqual(result["2026-08-19"].stages, {
        awake: 0,
        core: 240,
        deep: 60,
        rem: 120,
      });
      assert.equal(result["2026-08-19"].efficiency, 100);
      assert.equal(
          result["2026-08-19"].bedtime.toISOString(),
          "2026-08-19T06:00:00.000Z",
      );
      assert.equal(
          result["2026-08-19"].wakeTime.toISOString(),
          "2026-08-19T19:00:00.000Z",
      );
    });

test("does not label classic Fitbit sleep as Core sleep", () => {
  const sleep = {
    interval: {
      startTime: "2026-08-19T05:00:00Z",
      endTime: "2026-08-19T12:00:00Z",
      endUtcOffset: "-21600s",
    },
    type: "CLASSIC",
    stages: [
      stage("ASLEEP", "2026-08-19T05:00:00Z", "2026-08-19T11:30:00Z"),
      stage("AWAKE", "2026-08-19T11:30:00Z", "2026-08-19T12:00:00Z"),
    ],
  };

  assert.equal(sleepMinutes(sleep), 390);
  assert.equal(sleepDayKey(sleep), "2026-08-19");
  assert.equal(
      normalizeGoogleHealthSleep([{sleep}])["2026-08-19"].stages,
      undefined,
  );
});
