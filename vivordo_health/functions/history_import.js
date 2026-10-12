"use strict";

// History import (docs/scores.md §4): once per account the app imports 90
// days of Health history so the usuals exist on day one. Old days are
// scored once and then locked, so scoring them one write at a time would
// lock each day before all its data arrived (resting HR, then HRV, then
// sleep). While an import runs, the metrics trigger leaves old days alone;
// rebuildHistory then scores them oldest first, so each day's normal uses
// the days before it. Only days without a score are filled: a locked day
// keeps its score.

const {validDay} = require("./metrics_summary");

const IMPORT_DAYS = 90;
const DAY_MS = 86400000;
// An import the app didn't finish (closed mid-way) stops holding back the
// trigger after this; the next launch runs it again.
const STALE_MS = 60 * 60000;
// A finished import isn't rebuilt again within this, however often it's
// called.
const REBUILD_COOLDOWN_MS = 60 * 60000;

const millis = (value) => typeof value?.toMillis === "function" ?
  value.toMillis() : null;

/**
 * Whether a day is over in every time zone (the rule Capacity locks by).
 * @param {string} day Day key.
 * @param {Date} now Current time.
 * @return {boolean}
 */
function isOldDay(day, now) {
  return Date.parse(`${day}T00:00:00Z`) + DAY_MS + 14 * 3600000 <
    now.getTime();
}

/**
 * Whether an import is running (started, not finished, not stale).
 * @param {object|undefined} userData users/{uid} document data.
 * @param {Date} now Current time.
 * @return {boolean}
 */
function importRunning(userData, now) {
  const run = userData?.historyImport;
  const started = millis(run?.startedAt);
  return run?.state === "running" && started !== null &&
    now.getTime() - started < STALE_MS;
}

/**
 * Whether the metrics trigger should leave this write to rebuildHistory.
 * Reads the user document only for an old day.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {Date} now Current time.
 * @return {Promise<boolean>}
 */
async function leaveToImport(db, uid, day, now = new Date()) {
  if (!validDay(day) || !isOldDay(day, now)) return false;
  return importRunning((await db.doc(`users/${uid}`).get()).data(), now);
}

/**
 * Scores the imported days oldest first: heart-rate load, Capacity and
 * Physical Health for each day in the last [IMPORT_DAYS] that has metrics.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {Function} timestamp Server timestamp factory.
 * @param {Date} now Current time.
 * @return {Promise<object>} {state, days}.
 */
async function rebuildHistory(db, uid, timestamp, now = new Date()) {
  const {FieldPath} = require("firebase-admin/firestore");
  const {refreshCapacity} = require("./capacity");
  const {refreshActivityLoad} = require("./activity_load");
  const {refreshPhysicalHealth} = require("./physical_health");
  const user = db.doc(`users/${uid}`);
  const run = (await user.get()).data()?.historyImport;
  const finished = millis(run?.finishedAt);
  if (run?.state === "done" && finished !== null &&
      now.getTime() - finished < REBUILD_COOLDOWN_MS) {
    return {state: "done", days: 0};
  }
  const start = new Date(now.getTime() - IMPORT_DAYS * DAY_MS)
      .toISOString().slice(0, 10);
  const ids = (await user.collection("metrics_daily")
      .where(FieldPath.documentId(), ">=", start)
      .select().get()).docs.map((doc) => doc.id)
      .filter(validDay).sort();
  for (const day of ids) {
    // One day at a time: the heart-rate arrays make whole documents large.
    const data = (await user.collection("metrics_daily").doc(day).get())
        .data();
    await refreshActivityLoad(db, uid, day, data, timestamp);
    await refreshCapacity(db, uid, day, timestamp, now);
    await refreshPhysicalHealth(db, uid, day, timestamp);
  }
  await user.set({historyImport: {state: "done", finishedAt: timestamp(),
    scoredDays: ids.length}}, {merge: true});
  return {state: "done", days: ids.length};
}

module.exports = {IMPORT_DAYS, isOldDay, importRunning, leaveToImport,
  rebuildHistory};
