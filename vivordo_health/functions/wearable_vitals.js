"use strict";

const {whoopDateKey} = require("./whoop_reconciliation");

// These are daily observations, not the similarly named personal-range rollups.
const GOOGLE_DAILY_VITALS = [
  "daily-resting-heart-rate",
  "daily-heart-rate-variability",
  "daily-oxygen-saturation",
  "daily-respiratory-rate",
  "daily-vo2-max",
];

const number = (value) => {
  if ((typeof value !== "number" && typeof value !== "string") ||
      String(value).trim() === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const civilDay = (value) => {
  const date = value?.date || value;
  if (!Number.isInteger(date?.year) || !Number.isInteger(date?.month) ||
      !Number.isInteger(date?.day)) return null;
  const key = `${String(date.year).padStart(4, "0")}-` +
    `${String(date.month).padStart(2, "0")}-` +
    `${String(date.day).padStart(2, "0")}`;
  const parsed = new Date(`${key}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === key ? key : null;
};

const addVital = (days, day, key, raw, unit, extra = {}) => {
  const avg = number(raw);
  if (!day || avg === null || avg <= 0 ||
      (unit === "%" && avg > 100)) return;
  if (!days[day]) days[day] = {};
  days[day][key] = {avg, unit, ...extra};
};

/**
 * Normalizes dated Fitbit vitals without treating missing fields as zero.
 * RMSSD deliberately does not overwrite the existing Apple Health SDNN field.
 * @param {object} data Google Health responses keyed by data type.
 * @return {object} Daily metric maps (caller adds source and sync timestamp).
 */
function googleHealthVitals(data) {
  const days = {};
  for (const point of data["daily-resting-heart-rate"] || []) {
    const value = point.dailyRestingHeartRate;
    addVital(days, civilDay(value?.date), "resting_heart_rate",
        value?.beatsPerMinute, "bpm");
  }
  for (const point of data["daily-heart-rate-variability"] || []) {
    const value = point.dailyHeartRateVariability;
    addVital(days, civilDay(value?.date), "hrv_rmssd",
        value?.averageHeartRateVariabilityMilliseconds, "ms",
        {method: "rmssd"});
  }
  for (const point of data["daily-oxygen-saturation"] || []) {
    const value = point.dailyOxygenSaturation;
    // Bounds describe a distribution, not observed minimum/maximum readings.
    addVital(days, civilDay(value?.date), "blood_oxygen",
        value?.averagePercentage, "%");
  }
  for (const point of data["daily-vo2-max"] || []) {
    const value = point.dailyVo2Max;
    // Fitbit's cardio fitness score; "estimated" when its confidence is low.
    addVital(days, civilDay(value?.date), "vo2_max",
        value?.vo2MaxMillilitersPerKilogramPerMinute, "ml/kg/min",
        {estimated: value?.estimated === true});
  }
  for (const point of data["daily-respiratory-rate"] || []) {
    const value = point.dailyRespiratoryRate;
    addVital(days, civilDay(value?.date), "respiratory_rate",
        value?.breathsPerMinute, "brpm");
  }
  // A renamed Google field would otherwise be skipped silently. Log only the
  // response shape, never the health values.
  for (const [type, key] of [
    ["daily-resting-heart-rate", "resting_heart_rate"],
    ["daily-heart-rate-variability", "hrv_rmssd"],
    ["daily-oxygen-saturation", "blood_oxygen"],
    ["daily-respiratory-rate", "respiratory_rate"],
    ["daily-vo2-max", "vo2_max"],
  ]) {
    const points = data[type] || [];
    if (points.length > 0 && !Object.values(days).some((day) => day[key])) {
      console.warn(`[Google Health] ${type}: ${points.length} points, none ` +
        "parsed", Object.entries(points[0]).map(([field, value]) =>
        [field, value && typeof value === "object" ?
          Object.keys(value) : typeof value]));
    }
  }
  return days;
}

/**
 * Imports WHOOP measurements, never their proprietary Recovery/Strain scores.
 * Use the associated sleep's local wake day, not recovery upload/update time.
 * @param {object[]} sleeps WHOOP sleep records.
 * @param {object[]} recoveries WHOOP recovery records.
 * @return {object} Daily metric maps (caller adds source and sync timestamp).
 */
function whoopVitals(sleeps, recoveries = []) {
  const days = {};
  const sleepsById = new Map(sleeps.map((sleep) => [sleep.id, sleep]));
  // Stable selection if the API returns more than one main sleep for a day.
  for (const sleep of [...sleeps].sort((a, b) =>
    Date.parse(a.end) - Date.parse(b.end))) {
    if (sleep.nap || sleep.score_state !== "SCORED") continue;
    addVital(days, whoopDateKey(sleep.end, sleep.timezone_offset),
        "respiratory_rate", sleep.score?.respiratory_rate, "brpm");
  }
  for (const recovery of [...recoveries].sort((a, b) =>
    Date.parse(a.updated_at) - Date.parse(b.updated_at))) {
    if (recovery.score_state !== "SCORED") continue;
    const sleep = sleepsById.get(recovery.sleep_id);
    if (!sleep || sleep.nap) continue;
    const day = whoopDateKey(sleep.end, sleep.timezone_offset);
    const score = recovery.score;
    addVital(days, day, "resting_heart_rate", score?.resting_heart_rate, "bpm");
    addVital(days, day, "hrv_rmssd", score?.hrv_rmssd_milli, "ms",
        {method: "rmssd"});
    addVital(days, day, "blood_oxygen", score?.spo2_percentage, "%");
  }
  return days;
}

module.exports = {GOOGLE_DAILY_VITALS, googleHealthVitals, whoopVitals};
