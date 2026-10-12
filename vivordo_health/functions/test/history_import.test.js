"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {isOldDay, importRunning} = require("../history_import");

const now = new Date("2026-10-11T20:00:00Z");
const at = (iso) => ({toMillis: () => Date.parse(iso)});

test("old days are the ones over in every time zone, as Capacity locks them", () => {
  assert.equal(isOldDay("2026-10-11", now), false);
  // Locked 14 h after the day ends in UTC, as capacity.js does.
  assert.equal(isOldDay("2026-10-10", new Date("2026-10-11T13:00:00Z")), false);
  assert.equal(isOldDay("2026-10-10", now), true);
  assert.equal(isOldDay("2026-07-14", now), true);
});

test("an import holds back the trigger only while running and fresh", () => {
  assert.equal(importRunning(undefined, now), false);
  assert.equal(importRunning({historyImport: {state: "done", startedAt: at("2026-10-11T19:50:00Z")}}, now), false);
  assert.equal(importRunning({historyImport: {state: "running", startedAt: at("2026-10-11T19:50:00Z")}}, now), true);
  // Left running by an app closed mid-way: stale after an hour.
  assert.equal(importRunning({historyImport: {state: "running", startedAt: at("2026-10-11T18:30:00Z")}}, now), false);
  // Written by the app but the server timestamp hasn't resolved: not running.
  assert.equal(importRunning({historyImport: {state: "running"}}, now), false);
});
