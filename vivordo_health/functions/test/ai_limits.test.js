"use strict";
/* eslint-disable max-len */
const test = require("node:test");
const assert = require("node:assert/strict");
const {nextUsage} = require("../ai_limits");

test("daily usage resets each day and stops at the limit", () => {
  assert.deepEqual(nextUsage(undefined, "2026-10-01", 2), {day: "2026-10-01", count: 1});
  assert.deepEqual(nextUsage({day: "2026-10-01", count: 1}, "2026-10-01", 2), {day: "2026-10-01", count: 2});
  assert.equal(nextUsage({day: "2026-10-01", count: 2}, "2026-10-01", 2), null);
  assert.deepEqual(nextUsage({day: "2026-09-30", count: 2}, "2026-10-01", 2), {day: "2026-10-01", count: 1});
});
