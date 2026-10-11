"use strict";

// Heart-rate training load (docs/scores.md §4): how hard the body worked
// in a day, from per-minute heart rate, as Banister's TRIMP. Calculated when
// a day's heart rate syncs and saved small in scores_daily/{day}
// .activityLoad, so Capacity never reads the heart-rate arrays. A wellness
// estimate, not a medical measure.

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {validDay} = require("./metrics_summary");

const VERSION = 1;
// ACSM's moderate intensity starts at 40% of heart-rate reserve; below it
// is everyday living, which would otherwise outweigh a workout over a day.
const MIN_RESERVE = 0.4;
// Outside workouts an Apple Watch samples every few minutes: a reading
// stands for the time until the next one, up to this.
const MAX_GAP_MIN = 5;
// A day counts as measured with this many readings (a watch worn).
const MIN_READINGS = 60;
const DEFAULT_MAX_HR = 190;
const MINUTE_MS = 60000;
const SOURCES = ["apple_health", "whoop_ble", "fitbit_ble", "wearable_ble"];
const LIVE = new Set(["whoop_ble", "fitbit_ble", "wearable_ble"]);

const finite = (value) => typeof value === "number" && Number.isFinite(value);
const round1 = (value) => Math.round(value * 10 + 1e-9) / 10;
const ms = (value) => typeof value?.toMillis === "function" ?
  value.toMillis() : typeof value === "string" ? Date.parse(value) :
  finite(value) ? value : NaN;

/**
 * One reading per minute from a metrics_daily document: Apple Health and
 * Bluetooth wearables (a wearable wins a shared minute, as on the phone's
 * heart_rate_history.dart); camera scans are spot checks at rest and left
 * out.
 * @param {object} data metrics_daily document data.
 * @return {object[]} [{t (ms), bpm}], oldest first.
 */
function minuteReadings(data) {
  const sources = data?.heart_rate_sources ?? {};
  const lists = SOURCES.map((key) => [key, sources[key]]);
  const active = data?.heart_rate;
  if (active && !SOURCES.some((key) => key === active.source && sources[key])) {
    lists.push([active.source, active]);
  }
  const byMinute = new Map();
  for (const [key, metric] of lists) {
    if (!Array.isArray(metric?.entries)) continue;
    const live = LIVE.has(key);
    for (const entry of metric.entries) {
      const t = ms(entry?.timestamp);
      if (!finite(t) || !finite(entry?.bpm) || entry.bpm < 25 ||
          entry.bpm > 240) continue;
      const minute = Math.floor(t / MINUTE_MS);
      const old = byMinute.get(minute);
      if (old && old.live && !live) continue;
      if (old && old.live === live) {
        old.sum += entry.bpm;
        old.count++;
      } else {
        byMinute.set(minute, {live, sum: entry.bpm, count: 1});
      }
    }
  }
  return [...byMinute.entries()].sort((a, b) => a[0] - b[0])
      .map(([minute, v]) => ({t: minute * MINUTE_MS, bpm: v.sum / v.count}));
}

/**
 * The maximum heart rate: Tanaka (208 − 0.7 × age), or 190 without an
 * age, raised to the highest reading actually seen.
 * @param {number|null} age Years.
 * @param {number|null} peak Highest reading in the window.
 * @return {number} bpm.
 */
function maxHeartRate(age, peak) {
  const estimate = finite(age) ? 208 - 0.7 * age : DEFAULT_MAX_HR;
  return finite(peak) ? Math.max(estimate, Math.min(peak, 220)) : estimate;
}

/**
 * Banister's TRIMP over minutes at or above 40% of heart-rate reserve:
 * minutes × reserve × 0.64e^(1.92 × reserve) for men, 0.86e^(1.67 × reserve)
 * for women, the average of the two otherwise.
 * @param {object[]} readings [{t, bpm}] oldest first (minuteReadings).
 * @param {object} person {restingHr, maxHr, sex}.
 * @return {object} {trimp, minutes, readings, peakHr}.
 */
function heartRateLoad(readings, {restingHr, maxHr, sex}) {
  const weight = (r) => {
    const male = 0.64 * Math.exp(1.92 * r);
    const female = 0.86 * Math.exp(1.67 * r);
    return sex === "male" ? male : sex === "female" ? female :
      (male + female) / 2;
  };
  let trimp = 0;
  let minutes = 0;
  let peak = null;
  readings.forEach((reading, i) => {
    peak = peak === null ? reading.bpm : Math.max(peak, reading.bpm);
    const next = readings[i + 1];
    const span = next ?
      Math.min(MAX_GAP_MIN, Math.max(1, (next.t - reading.t) / MINUTE_MS)) : 1;
    const reserve = (reading.bpm - restingHr) / (maxHr - restingHr);
    if (reserve < MIN_RESERVE) return;
    const r = Math.min(1, reserve);
    trimp += span * r * weight(r);
    minutes += span;
  });
  return {trimp: round1(trimp), minutes: Math.round(minutes),
    readings: readings.length, peakHr: peak === null ? null : Math.round(peak)};
}

/**
 * The day's resting heart rate: Health's or the wearable's, else the lowest
 * tenth of the day's readings.
 * @param {object} data metrics_daily document data.
 * @param {object[]} readings minuteReadings.
 * @return {number|null} bpm.
 */
function restingFor(data, readings) {
  if (finite(data?.resting_heart_rate?.avg)) return data.resting_heart_rate.avg;
  if (readings.length < MIN_READINGS) return null;
  const sorted = readings.map((r) => r.bpm).sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length * 0.1)];
}

/**
 * A day's heart-rate load, or null without enough readings to call it
 * measured (a watch not worn that day).
 * @param {object} data metrics_daily document data.
 * @param {object} profile {age, sex}.
 * @return {object|null} {version, trimp, minutes, readings, peakHr,
 *   restingHr, maxHr}.
 */
function computeActivityLoad(data, profile = {}) {
  const readings = minuteReadings(data);
  if (readings.length < MIN_READINGS) return null;
  const restingHr = restingFor(data, readings);
  if (!finite(restingHr)) return null;
  const peak = Math.max(...readings.map((r) => r.bpm));
  const maxHr = maxHeartRate(profile.age, peak);
  if (maxHr - restingHr < 30) return null;
  return {version: VERSION,
    ...heartRateLoad(readings, {restingHr, maxHr, sex: profile.sex}),
    restingHr: Math.round(restingHr), maxHr: Math.round(maxHr)};
}

/**
 * Whether a metrics_daily write changed the heart rate the load reads.
 * Cheap: entry counts and last timestamps per source.
 * @param {object|undefined} before Previous document data.
 * @param {object|undefined} after New document data.
 * @return {boolean} True when the load should be recalculated.
 */
function heartRateChanged(before, after) {
  const pick = (d) => [...SOURCES.map((k) => d?.heart_rate_sources?.[k]),
    d?.heart_rate].map((m) => [m?.entries?.length ?? 0,
    ms(m?.entries?.at?.(-1)?.timestamp) || 0]).concat(
      [d?.resting_heart_rate?.avg ?? null]);
  return !isDeepStrictEqual(pick(before), pick(after));
}

/**
 * Recalculates and saves a day's heart-rate load in scores_daily/{day}
 * from the metrics_daily document the trigger already has.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {object|undefined} data The day's metrics_daily data.
 * @param {Function} timestamp Server timestamp factory.
 * @return {Promise<string>} "written", "unchanged", "ignored" or
 *   "unavailable".
 */
async function refreshActivityLoad(db, uid, day, data, timestamp) {
  if (!validDay(day)) return "ignored";
  const user = db.doc(`users/${uid}`);
  const stored = (await user.get()).data()?.preferences?.personalProfile ?? {};
  const birthYear = finite(stored.birthYear) ? stored.birthYear : null;
  const profile = {
    age: birthYear === null ? null :
      Number(day.slice(0, 4)) - birthYear,
    sex: stored.sex ?? null,
  };
  const load = data ? computeActivityLoad(data, profile) : null;
  const target = user.collection("scores_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  return db.runTransaction(async (tx) => {
    const [owner, tombstone, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    const old = existing.data()?.activityLoad ?? null;
    const oldContent = old ? {...old} : null;
    if (oldContent) delete oldContent.computedAt;
    if (isDeepStrictEqual(load, oldContent)) return "unchanged";
    tx.set(target, {
      activityLoad: load ? {...load, computedAt: timestamp()} : null,
    }, {merge: true});
    return "written";
  });
}

module.exports = {
  VERSION, MIN_READINGS, minuteReadings, maxHeartRate, heartRateLoad,
  computeActivityLoad, heartRateChanged, refreshActivityLoad,
};
