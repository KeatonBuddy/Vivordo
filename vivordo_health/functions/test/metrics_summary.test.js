"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {projectActivity, refreshActivitySummary, validDay} = require("../metrics_summary");

function fixture() {
  const documents = new Map([["users/a", {}], ["users/a/metrics_daily/2026-09-24", {
    steps: {sum: 50, source: "apple_health"}, heart_rate: {entries: [{bpm: 100}]},
  }]]);
  let writes = 0;
  const ref = (path) => ({path, collection: (name) => ({doc: (id) => ref(`${path}/${name}/${id}`)})});
  const db = {doc: ref, runTransaction: async (action) => action({
    get: async (r) => ({exists: documents.has(r.path), data: () => documents.get(r.path)}),
    set: (r, data) => {
      documents.set(r.path, data); writes++;
    },
    delete: (r) => {
      documents.delete(r.path); writes++;
    },
  })};
  return {documents, db, writes: () => writes,
    refresh: () => refreshActivitySummary(db, "a", "2026-09-24", () => "timestamp")};
}

test("projection is compact, keeps zero/missing distinct and rejects invalid totals", () => {
  const result = projectActivity({steps: {sum: 0}, active_calories: {sum: -1},
    exercise_time: {sum: Infinity}, heart_rate: {entries: [1, 2, 3]}});
  assert.equal(result.steps.sum, 0);
  assert.equal(result.active_calories.sum, null);
  assert.equal(result.exercise_time.sum, null);
  assert.equal(result.heart_rate, undefined);
  assert.equal(result.schemaVersion, 1);
});

test("duplicates and unrelated metric changes do not rewrite summary", async () => {
  const f = fixture();
  assert.equal(await f.refresh(), "written");
  assert.equal(await f.refresh(), "unchanged");
  f.documents.get("users/a/metrics_daily/2026-09-24").heart_rate.entries.push(200);
  assert.equal(await f.refresh(), "unchanged");
  assert.equal(f.writes(), 1);
});

test("delayed invocation reads current values; corrections and deletions converge", async () => {
  const f = fixture();
  await f.refresh();
  f.documents.set("users/a/metrics_daily/2026-09-24", {steps: {sum: 25}});
  await f.refresh();
  assert.equal(f.documents.get("users/a/metric_summaries_daily/2026-09-24").steps.sum, 25);
  assert.equal(await f.refresh(), "unchanged");
  f.documents.delete("users/a/metrics_daily/2026-09-24");
  assert.equal(await f.refresh(), "deleted");
  assert.equal(f.documents.has("users/a/metric_summaries_daily/2026-09-24"), false);
});

test("removed metrics clear old values rather than merging stale fields", async () => {
  const f = fixture();
  await f.refresh();
  f.documents.set("users/a/metrics_daily/2026-09-24", {});
  await f.refresh();
  assert.equal(f.documents.get("users/a/metric_summaries_daily/2026-09-24").steps.sum, null);
});

test("account tombstone and absent owner prevent resurrection", async () => {
  const f = fixture();
  await f.refresh();
  const hash = crypto.createHash("sha256").update("a").digest("hex");
  f.documents.set(`account_deletion_jobs/${hash}`, {status: "complete"});
  await f.refresh();
  assert.equal(f.documents.has("users/a/metric_summaries_daily/2026-09-24"), false);
  f.documents.delete(`account_deletion_jobs/${hash}`);
  f.documents.delete("users/a");
  await f.refresh();
  assert.equal(f.documents.has("users/a/metric_summaries_daily/2026-09-24"), false);
});

test("rejects invalid dates and non-day metric documents", async () => {
  const f = fixture();
  assert.equal(validDay("2026-02-30"), false);
  assert.equal(validDay("2026-09-24"), true);
  assert.equal(await refreshActivitySummary(f.db, "a", "stress_summary", () => 0), "ignored");
  assert.equal(f.writes(), 0);
});
