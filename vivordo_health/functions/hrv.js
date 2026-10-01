"use strict";

// HRV comes in kinds that can't be compared or converted: Apple Health's
// daytime SDNN and each wearable's overnight RMSSD (WHOOP and Fitbit also
// measure in different windows of the night). Scores compare HRV with the
// person's own normal, so each one only uses readings of a single kind.
// Mirrored in lib/src/utils/heart_health_score.dart.

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
 * @return {object} {kind, value, history}. history lines up with the input
 *   days (null where a day has no reading of that kind); kind and value are
 *   null when today has no HRV.
 */
function pickHrv(today, history, minBaseline) {
  const options = HRV_KINDS.filter((kind) => today?.[kind] !== undefined)
      .map((kind) => ({kind, value: today[kind],
        history: history.map((day) => day?.[kind] ?? null)}));
  return options.find((option) =>
    option.history.filter((value) => value !== null).length >= minBaseline) ??
    options[0] ?? {kind: null, value: null, history: history.map(() => null)};
}

module.exports = {HRV_KINDS, hrvReadings, pickHrv};
