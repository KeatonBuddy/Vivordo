"use strict";

// HRV comes in kinds that can't be compared or converted: Apple Health's
// daytime SDNN and each wearable's overnight RMSSD (WHOOP and Fitbit also
// measure in different windows of the night). Scores compare HRV with the
// person's own normal, so each one only uses readings of a single kind.
// hrvReadings is mirrored in lib/src/utils/hrv.dart.

// The connected wearable first, then Apple Health.
const HRV_KINDS = ["rmssd:whoop", "rmssd:fitbit", "sdnn"];

const valid = (value) =>
  typeof value === "number" && Number.isFinite(value) && value > 0;

/**
 * A day's HRV readings keyed by kind.
 * @param {object} data metrics_daily document data.
 * @return {object} e.g. {"rmssd:whoop": 44, "sdnn": 61}.
 */
function hrvReadings(data) {
  const readings = {};
  const rmssd = data?.hrv_rmssd;
  const kind = `rmssd:${rmssd?.source}`;
  if (HRV_KINDS.includes(kind) && valid(rmssd.avg)) readings[kind] = rmssd.avg;
  if (valid(data?.hrv?.avg)) readings.sdnn = data.hrv.avg;
  return readings;
}

/**
 * Today's HRV with the same-kind values of earlier days. Prefers the
 * wearable, but keeps using a kind that already has a normal while a newly
 * connected wearable builds its own, so HRV isn't dropped for a week.
 * @param {object} today hrvReadings of the scored day.
 * @param {object[]} history hrvReadings of earlier days.
 * @param {number} minBaseline Readings a kind needs to have a normal.
 * @param {string[]} kinds Kinds in order of preference (resting heart rate
 *   uses the same rule with RESTING_HR_KINDS).
 * @return {object} {kind, value, history}. history lines up with the input
 *   days (null where a day has no reading of that kind); kind and value are
 *   null when today has no HRV.
 */
function pickHrv(today, history, minBaseline, kinds = HRV_KINDS) {
  const options = kinds.filter((kind) => today?.[kind] !== undefined)
      .map((kind) => ({kind, value: today[kind],
        history: history.map((day) => day?.[kind] ?? null)}));
  const hasNormal = (option) =>
    option.history.filter((value) => value !== null).length >= minBaseline;
  // A reading with a normal, else a normal to keep (a kind listed with a
  // null value today), else whatever was measured.
  return options.find((option) => option.value !== null && hasNormal(option)) ??
    options.find(hasNormal) ??
    options.find((option) => option.value !== null) ??
    {kind: null, value: null, history: history.map(() => null)};
}

// Resting heart rate: Health's or the wearable's, else the lowest of the
// night's readings while asleep (sleeping_heart_rate, written by the app's
// Health sync for wearables that don't write a resting heart rate). The
// sleeping one runs a few bpm lower, so the two are never mixed either.
const RESTING_HR_KINDS = ["resting", "sleeping"];

/**
 * A day's resting heart rate readings keyed by kind.
 * @param {object} data metrics_daily document data.
 * @return {object} e.g. {resting: 52, sleeping: 48}.
 */
function restingHrReadings(data) {
  const readings = {};
  if (valid(data?.resting_heart_rate?.avg)) {
    readings.resting = data.resting_heart_rate.avg;
  }
  if (valid(data?.sleeping_heart_rate?.avg)) {
    readings.sleeping = data.sleeping_heart_rate.avg;
  }
  return readings;
}

module.exports = {HRV_KINDS, RESTING_HR_KINDS, hrvReadings, restingHrReadings,
  pickHrv};
