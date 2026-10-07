"use strict";

// Training load (docs/scores.md §4): this week's activity against the
// person's usual week, as a state from Steady to Strained. Each day is
// relative to its own measure's usual (heart-rate load on a measured day,
// minutes otherwise; capacity.js physicalLoads), so the two are never added
// together. Calculated with Capacity each morning and saved in
// scores_daily/{day}.trainingLoad. A wellness signal, not a diagnosis.

const VERSION = 1;
const HARD_DAY = 1.5; // × an ordinary active day
const HIGH = 1.5; // this week ÷ the usual week
const BUILDING = 1.3;
const LIGHTER = 0.8;
const HIGH_HARD_DAYS = 3;
// The usual week is the 4 weeks before this one (days 8–35), so this week
// doesn't raise its own bar. It needs most of those days on record and at
// least an ordinary active day a week.
const MIN_COVERED_DAYS = 21;
const MIN_USUAL_WEEK = 1;
// The body agrees on a morning when HRV is 5% under its normal or resting
// heart rate is 3 bpm over; Strained needs 2 of the last 3 mornings.
const HRV_DROP = 0.05;
const RESTING_RISE = 3;
const DAY_MS = 86400000;

const finite = (value) => typeof value === "number" && Number.isFinite(value);
const round = (value, places) => {
  const f = 10 ** places;
  return Math.round(value * f + 1e-9) / f;
};

/**
 * A day's load against its own measure's usual: 1.0 is an ordinary active
 * day, 2.0 twice that. Heart-rate load when the day was measured (and the
 * person has a heart-rate usual), minutes otherwise; null with neither.
 * @param {string} key Day key.
 * @param {object} loads {heartOn, heartBase, minutesOn, minutesBase}: day
 *   key -> load maps and the usuals they're divided by (bigDayScale base).
 * @return {object|null} {value, kind}.
 */
function relativeDay(key, loads) {
  const {heartOn, heartBase, minutesOn, minutesBase} = loads;
  if (finite(heartBase) && heartBase > 0 && heartOn?.has(key)) {
    return {value: heartOn.get(key) / heartBase, kind: "heart"};
  }
  if (finite(minutesBase) && minutesBase > 0 && minutesOn?.has(key)) {
    return {value: minutesOn.get(key) / minutesBase, kind: "minutes"};
  }
  return null;
}

/**
 * Training load for a day, from the 35 days before it.
 * @param {object} input
 * @param {string} input.day The day it's for (today).
 * @param {object} input.loads See relativeDay.
 * @param {object[]} input.mornings The last 3 mornings, today first:
 *   {hrv, restingHr}, either may be null.
 * @param {number|null} input.hrvNormal The person's 90-day HRV (same kind).
 * @param {number|null} input.restingHrNormal Their 90-day resting HR.
 * @param {string|null} input.previousState Yesterday's state, so High holds
 *   until this week drops below 1.3× usual.
 * @return {object} The record (state "learning" until there's a usual).
 */
function trainingLoadFor({day, loads, mornings = [], hrvNormal = null,
  restingHrNormal = null, previousState = null}) {
  const key = (k) => new Date(Date.parse(`${day}T00:00:00Z`) - k * DAY_MS)
      .toISOString().slice(0, 10);
  const usualDays = [];
  for (let k = 8; k <= 35; k++) usualDays.push(relativeDay(key(k), loads));
  const covered = usualDays.filter(Boolean).length;
  const usualWeek = usualDays.reduce((sum, d) => sum + (d?.value ?? 0), 0) / 4;
  if (covered < MIN_COVERED_DAYS || usualWeek < MIN_USUAL_WEEK) {
    return {version: VERSION, state: "learning", coveredDays: covered};
  }

  const week = [];
  for (let k = 7; k >= 1; k--) {
    const d = relativeDay(key(k), loads);
    week.push({day: key(k), value: round(d?.value ?? 0, 2),
      kind: d?.kind ?? null});
  }
  const thisWeek = week.reduce((sum, d) => sum + d.value, 0);
  const ratio = thisWeek / usualWeek;
  const hardDays = week.filter((d) => d.value >= HARD_DAY).length;
  const kinds = new Set(week.map((d) => d.kind).filter(Boolean));

  const hrvLow = (m) => finite(m?.hrv) && finite(hrvNormal) &&
    m.hrv < hrvNormal * (1 - HRV_DROP);
  const restingHigh = (m) => finite(m?.restingHr) &&
    finite(restingHrNormal) && m.restingHr >= restingHrNormal + RESTING_RISE;
  const recent = mornings.slice(0, 3);
  const measured = recent.filter((m) =>
    (finite(m?.hrv) && finite(hrvNormal)) ||
    (finite(m?.restingHr) && finite(restingHrNormal))).length;
  const off = recent.filter((m) => hrvLow(m) || restingHigh(m)).length;
  const today = recent[0];
  const body = {
    mornings: measured,
    hrvLow: recent.filter(hrvLow).length,
    restingHigh: recent.filter(restingHigh).length,
    restingHrChange: finite(today?.restingHr) && finite(restingHrNormal) ?
      round(today.restingHr - restingHrNormal, 1) : null,
    agrees: off >= 2,
  };

  const wasHigh = previousState === "high" || previousState === "strained";
  const high = (ratio >= HIGH && hardDays >= HIGH_HARD_DAYS) ||
    (wasHigh && ratio >= BUILDING);
  const state = high ? (body.agrees ? "strained" : "high") :
    ratio >= BUILDING ? "building" :
    ratio < LIGHTER ? "lighter" : "steady";
  return {
    version: VERSION, state, ratio: round(ratio, 2),
    thisWeek: round(thisWeek, 1), usualWeek: round(usualWeek, 1), hardDays,
    kind: kinds.size === 0 ? null : kinds.size === 1 ? [...kinds][0] : "mixed",
    days: week, body,
  };
}

module.exports = {VERSION, HARD_DAY, relativeDay, trainingLoadFor};
