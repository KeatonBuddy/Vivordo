"use strict";

// Capacity: the energy someone has today, 0–100 (docs/scores.md §4).
// Each ingredient is a 0–100 sub-score, mostly against the person's own
// 90-day normal. Wellness estimate, not a medical score.

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {validDay} = require("./metrics_summary");

const VERSION = 1;
const WEIGHTS = {sleep: 45, body: 35, recovery: 20, checkIn: 15};
const NEUTRAL_BODY = 70; // a normal night
const HISTORY_DAYS = 90;
const MIN_BASELINE = 7; // HRV / resting HR readings needed for a normal
const DAY_MS = 86400000;

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const clamp = (value) => Math.min(100, Math.max(0, value));
const finite = (value) => typeof value === "number" && Number.isFinite(value);

/**
 * Minutes between two clock times, the short way round midnight.
 * @param {number} a Minutes after midnight.
 * @param {number} b Minutes after midnight.
 * @return {number} 0–720.
 */
function clockGap(a, b) {
  const gap = Math.abs(a - b) % 1440;
  return Math.min(gap, 1440 - gap);
}

/**
 * Average clock time of bedtimes that straddle midnight (circular mean).
 * @param {number[]} minutes Minutes after midnight.
 * @return {number} Minutes after midnight.
 */
function usualClockTime(minutes) {
  let x = 0;
  let y = 0;
  for (const m of minutes) {
    x += Math.cos(m / 1440 * 2 * Math.PI);
    y += Math.sin(m / 1440 * 2 * Math.PI);
  }
  const angle = Math.atan2(y, x);
  return ((angle / (2 * Math.PI)) * 1440 + 1440) % 1440;
}

/**
 * The person's sleep need: 90-day median, kept within 7–9 h; 8 h until
 * there are 14 nights.
 * @param {number[]} nights Hours slept on earlier nights.
 * @return {number} Hours.
 */
function sleepNeed(nights) {
  if (nights.length < 14) return 8;
  return Math.min(9, Math.max(7, median(nights)));
}

/**
 * Capacity for one day.
 * @param {object} input
 * @param {object} input.today {sleepHours, bedtimeMin, hrv, restingHr,
 *   yesterdayEffort, usualEffort, checkInFeel, checkInSleep}; any may be
 *   null. bedtimeMin is minutes after midnight in a fixed clock (UTC is
 *   fine: only gaps between bedtimes are used).
 * @param {object[]} input.history Earlier days in the last 90, any order:
 *   {sleepHours, bedtimeMin, hrv, restingHr}.
 * @return {object|null} Capacity record, or null when there is no sleep
 *   and no measured body data (never guessed).
 */
function computeCapacity({today, history}) {
  const need = sleepNeed(history.map((d) => d.sleepHours)
      .filter((h) => finite(h) && h > 0));

  let sleep = null;
  let bedtimeOffsetMin = null;
  if (finite(today.sleepHours) && today.sleepHours > 0) {
    sleep = 100 * Math.min(1, today.sleepHours / need);
    if (today.sleepHours < 5) sleep *= 0.7;
    const recentBedtimes = history.slice(-14).map((d) => d.bedtimeMin)
        .filter(finite);
    if (finite(today.bedtimeMin) && recentBedtimes.length >= 5) {
      bedtimeOffsetMin = Math.round(
          clockGap(today.bedtimeMin, usualClockTime(recentBedtimes)));
      if (bedtimeOffsetMin > 60) sleep -= 10;
    }
    sleep = clamp(sleep);
  }

  const normal = (key) => {
    const values = history.map((d) => d[key]).filter(finite);
    return values.length >= MIN_BASELINE ? median(values) : null;
  };
  const hrvNormal = normal("hrv");
  const restingHrNormal = normal("restingHr");
  const bodyParts = [];
  if (finite(today.hrv) && hrvNormal) {
    bodyParts.push(clamp(70 + 100 * (today.hrv / hrvNormal - 1)));
  }
  if (finite(today.restingHr) && restingHrNormal) {
    bodyParts.push(clamp(70 - 6 * (today.restingHr - restingHrNormal)));
  }
  const bodyMeasured = bodyParts.length > 0;
  if (sleep === null && !bodyMeasured) return null;
  const body = bodyMeasured ?
    bodyParts.reduce((a, b) => a + b) / bodyParts.length : NEUTRAL_BODY;

  const recovery = finite(today.yesterdayEffort) && finite(today.usualEffort) ?
    clamp(100 - Math.max(0, today.yesterdayEffort - today.usualEffort)) :
    null;
  const checkInParts = [today.checkInFeel, today.checkInSleep].filter(finite);
  const checkIn = checkInParts.length ?
    clamp(checkInParts.reduce((a, b) => a + b) / checkInParts.length) : null;

  const parts = {sleep, body, recovery, checkIn};
  let total = 0;
  let weight = 0;
  for (const [name, value] of Object.entries(parts)) {
    if (value === null) continue;
    total += WEIGHTS[name] * value;
    weight += WEIGHTS[name];
  }
  const score = Math.round(total / weight);
  const round1 = (value) => value === null ? null : Math.round(value * 10) / 10;
  return {
    score,
    label: score >= 80 ? "high" : score >= 50 ? "moderate" : "low",
    version: VERSION,
    provisional: sleep === null, // recalculates when last night's sleep syncs
    parts: {sleep: round1(sleep), body: round1(body),
      recovery: round1(recovery), checkIn: round1(checkIn)},
    bodyMeasured,
    sleepHours: finite(today.sleepHours) ? today.sleepHours : null,
    sleepNeed: need,
    bedtimeOffsetMin,
    hrv: finite(today.hrv) ? today.hrv : null,
    hrvNormal,
    restingHr: finite(today.restingHr) ? today.restingHr : null,
    restingHrNormal,
  };
}

/**
 * The inputs Capacity reads from a metrics_daily document.
 * @param {object} data metrics_daily document data.
 * @return {object} {sleepHours, bedtimeMin, hrv, restingHr}.
 */
function capacityInputs(data) {
  const bedtime = data?.sleep?.bedtime;
  const date = typeof bedtime?.toDate === "function" ? bedtime.toDate() : null;
  return {
    sleepHours: finite(data?.sleep?.avg) ? data.sleep.avg : null,
    bedtimeMin: date ? date.getUTCHours() * 60 + date.getUTCMinutes() : null,
    hrv: finite(data?.hrv?.avg) ? data.hrv.avg : null,
    restingHr: finite(data?.resting_heart_rate?.avg) ?
      data.resting_heart_rate.avg : null,
  };
}

/**
 * Recalculates and saves a day's Capacity in users/{uid}/scores_daily/{day}.
 * A day is final once it is over in every time zone; final days are never
 * rewritten.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {Function} timestamp Server timestamp factory.
 * @param {Date} now Current time.
 * @return {Promise<string>} Outcome.
 */
async function refreshCapacity(db, uid, day, timestamp, now = new Date()) {
  if (!validDay(day)) return "ignored";
  const user = db.doc(`users/${uid}`);
  const start = new Date(Date.parse(`${day}T00:00:00Z`) -
    HISTORY_DAYS * DAY_MS).toISOString().slice(0, 10);
  const {FieldPath} = require("firebase-admin/firestore");
  // Only the three fields Capacity reads, never the heart-rate arrays.
  const snapshot = await user.collection("metrics_daily")
      .where(FieldPath.documentId(), ">=", start)
      .where(FieldPath.documentId(), "<=", day)
      .select("sleep", "hrv", "resting_heart_rate")
      .get();
  let todayData = null;
  const history = [];
  for (const doc of snapshot.docs) {
    if (!validDay(doc.id)) continue;
    if (doc.id === day) todayData = doc.data();
    else history.push({day: doc.id, ...capacityInputs(doc.data())});
  }
  history.sort((a, b) => a.day.localeCompare(b.day));
  const capacity = todayData ?
    computeCapacity({today: capacityInputs(todayData), history}) : null;

  const target = user.collection("scores_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  // The day is over everywhere 14 h after it ends in UTC (UTC+14).
  const final = Date.parse(`${day}T00:00:00Z`) + DAY_MS + 14 * 3600000 <
    now.getTime();
  return db.runTransaction(async (tx) => {
    const [owner, tombstone, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    const old = existing.data()?.capacity;
    if (old?.final) return "final";
    const next = capacity && {...capacity, final};
    const oldContent = old ? {...old} : null;
    if (oldContent) delete oldContent.computedAt;
    if (isDeepStrictEqual(next, oldContent)) return "unchanged";
    tx.set(target, {
      capacity: next ? {...next, computedAt: timestamp()} : null,
    }, {merge: true});
    return "written";
  });
}

/**
 * Whether a metrics_daily write changed anything Capacity reads.
 * @param {object|undefined} before Previous document data.
 * @param {object|undefined} after New document data.
 * @return {boolean} True when Capacity should be recalculated.
 */
function capacityInputsChanged(before, after) {
  return !isDeepStrictEqual(capacityInputs(before), capacityInputs(after));
}

module.exports = {
  VERSION, WEIGHTS, computeCapacity, capacityInputs, capacityInputsChanged,
  refreshCapacity, sleepNeed, clockGap, usualClockTime,
};
