"use strict";

// Burnout early warning: compares the last 14 days of each signal with the
// person's own normal (8 weeks, ending 2 weeks before the recent window) and
// needs two groups of signals to agree before raising a warning. Thresholds
// are starting values to tune against real histories; this is a wellness
// signal, not a diagnosis.

const DAY_MS = 86400000;
const RECENT_DAYS = 14;
// The gap keeps a month of building strain out of "normal", so it is not
// absorbed before it is flagged.
// ponytail: strain lasting ~10+ weeks still becomes the new normal; freeze
// the baseline while at watch/warning if that turns out to matter.
const GAP_DAYS = 14;
const BASELINE_DAYS = 56;
const MIN_RECENT = 7;
const MIN_BASELINE = 14;
const PERSISTENT_SHARE = 0.65;
const ELEVATED = 1;
const HIGH = 2;
const WARNING_AFTER_DAYS = 7; // two strained weekly checks in a row
const CALM_DAYS_TO_CLEAR = 7;
const NOTIFY_COOLDOWN_DAYS = 7;

// direction: +1 when a rise is worse, -1 when a fall is worse.
// minChange: smallest shift that counts; relative: as a share of the normal.
const SIGNALS = {
  stress: {group: "recovery", direction: 1, minChange: 3, label: "Stress"},
  restingHeartRate: {group: "recovery", direction: 1, minChange: 2,
    label: "Resting heart rate", unit: " bpm"},
  hrv: {group: "recovery", direction: -1, minChange: 0.05, relative: true,
    label: "HRV", unit: " ms"},
  sleepHours: {group: "recovery", direction: -1, minChange: 1 / 3,
    label: "Sleep"},
  exerciseMinutes: {group: "recovery", direction: -1, minChange: 10,
    label: "Exercise", unit: " min"},
  mood: {group: "mood", direction: -1, minChange: 5, label: "Mood"},
};

/**
 * One day's signals from a metrics_daily document; absent values are null.
 * @param {object} data metrics_daily document data.
 * @return {object} Signal values keyed like SIGNALS.
 */
function dailySignals(data) {
  const num = (value) =>
    typeof value === "number" && Number.isFinite(value) ? value : null;
  return {
    stress: num(data?.stress?.avg) ?? num(data?.stress?.current),
    restingHeartRate: num(data?.resting_heart_rate?.avg),
    hrv: num(data?.hrv?.avg),
    sleepHours: num(data?.sleep?.avg),
    exerciseMinutes: num(data?.exercise_time?.sum),
    mood: num(data?.mood?.avg),
  };
}

const dayIndex = (day) => Math.round(Date.parse(`${day}T00:00:00Z`) / DAY_MS);
const dayKey = (index) => new Date(index * DAY_MS).toISOString().slice(0, 10);

/**
 * Median of a non-empty list.
 * @param {number[]} values Values.
 * @return {number} Median.
 */
function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * How far one signal has drifted from its normal, worse-is-positive.
 * @param {object} config Entry from SIGNALS.
 * @param {number[]} recent Last 14 days' values.
 * @param {number[]} baseline The 8 weeks before.
 * @return {object|null} Score details, or null without enough data.
 */
function scoreSignal(config, recent, baseline) {
  if (recent.length < MIN_RECENT || baseline.length < MIN_BASELINE) {
    return null;
  }
  const usual = median(baseline);
  const now = median(recent);
  const minChange = config.relative ?
    Math.abs(usual) * config.minChange : config.minChange;
  // Robust spread (scaled median absolute deviation), floored so a very
  // steady normal does not turn a small change into a large score.
  const spread = Math.max(
      1.4826 * median(baseline.map((value) => Math.abs(value - usual))),
      minChange);
  const shift = config.direction * (now - usual);
  const score = shift < minChange ? 0 : shift / spread;
  const worseDays = recent.filter(
      (value) => config.direction * (value - usual) > 0).length;
  const persistent = worseDays / recent.length >= PERSISTENT_SHARE;
  return {
    score, usual, recent: now, worseDays, days: recent.length,
    elevated: persistent && score >= ELEVATED,
    high: persistent && score >= HIGH,
  };
}

/**
 * Evaluates one night from raw daily signals.
 * @param {Map<string, object>} byDay Day key -> dailySignals result.
 * @param {string} today Day key being evaluated.
 * @return {object} Signals, groups and the night's raw condition.
 */
function assess(byDay, today) {
  const end = dayIndex(today);
  const signals = {};
  for (const [name, config] of Object.entries(SIGNALS)) {
    const recent = [];
    const baseline = [];
    for (let i = end - RECENT_DAYS - GAP_DAYS - BASELINE_DAYS + 1;
      i <= end; i++) {
      const value = byDay.get(dayKey(i))?.[name];
      if (value == null) continue;
      if (i > end - RECENT_DAYS) recent.push(value);
      else if (i <= end - RECENT_DAYS - GAP_DAYS) baseline.push(value);
    }
    const result = scoreSignal(config, recent, baseline);
    if (result) signals[name] = {...result, group: config.group};
  }
  // A group is strained when any of its signals is: averaging would let
  // normal sleep and heart rate hide two weeks of rising stress.
  const groups = {};
  for (const [name, signal] of Object.entries(signals)) {
    if (!groups[signal.group]) {
      groups[signal.group] = {signals: [], elevated: 0, high: false};
    }
    const group = groups[signal.group];
    group.signals.push(name);
    if (signal.elevated) group.elevated++;
    if (signal.high) group.high = true;
  }
  for (const group of Object.values(groups)) {
    group.strained = group.elevated > 0;
  }
  const list = Object.values(groups);
  const strained = list.filter((group) => group.strained);
  return {
    signals, groups,
    enoughData: list.length >= 2,
    strainedGroups: strained.length,
    // A high signal in one group backed by strain in another.
    acute: list.some((group) => group.high &&
      strained.some((other) => other !== group)),
    watch: strained.length >= 2 || list.some((group) => group.elevated >= 2),
  };
}

/**
 * Plain-language reasons: the three most-drifted signals.
 * @param {object} signals Scored signals from assess().
 * @return {string[]} Reasons, worst first.
 */
function reasons(signals) {
  const format = (name, value) => {
    const config = SIGNALS[name];
    if (name === "sleepHours") {
      const hours = Math.floor(value);
      const minutes = Math.round((value - hours) * 60);
      return `${hours}h ${String(minutes).padStart(2, "0")}m`;
    }
    return `${Math.round(value)}${config.unit ?? ""}`;
  };
  return Object.entries(signals)
      .filter(([, signal]) => signal.elevated)
      .sort(([, a], [, b]) => b.score - a.score)
      .slice(0, 3)
      .map(([name, signal]) => `${SIGNALS[name].label} has been ` +
        `${format(name, signal.recent)} vs your usual ` +
        `${format(name, signal.usual)} on most days for 2 weeks`);
}

/**
 * One nightly evaluation, carrying state from the previous night.
 * @param {Map<string, object>} byDay Day key -> dailySignals result.
 * @param {string} today Day key being evaluated.
 * @param {object|null} previous State returned by the previous night.
 * @return {object} {level, reasons, notify, state}.
 */
function evaluateNight(byDay, today, previous) {
  const state = {strainedDays: 0, calmDays: 0, level: "steady",
    lastNotified: null, ...previous};
  const night = assess(byDay, today);
  if (!night.enoughData) {
    return {level: "learning", reasons: [], notify: false,
      state: {...state, strainedDays: 0, calmDays: 0, level: "learning"}};
  }
  state.strainedDays = night.strainedGroups >= 2 ? state.strainedDays + 1 : 0;
  state.calmDays = night.strainedGroups === 0 ? state.calmDays + 1 : 0;

  let level;
  if (night.acute || state.strainedDays >= WARNING_AFTER_DAYS) {
    level = "warning";
  } else if (state.level === "warning" &&
      state.calmDays < CALM_DAYS_TO_CLEAR) {
    level = "warning"; // hold until a calm week, so it doesn't flicker
  } else {
    level = night.watch ? "watch" : "steady";
  }

  const sinceNotified = state.lastNotified == null ? Infinity :
    dayIndex(today) - dayIndex(state.lastNotified);
  const notify = level === "warning" && state.level !== "warning" &&
    sinceNotified >= NOTIFY_COOLDOWN_DAYS;
  return {
    level, reasons: reasons(night.signals), notify,
    state: {...state, level, lastNotified: notify ? today : state.lastNotified},
  };
}

/**
 * Replays nightly evaluations over a day range (tests and backfills).
 * @param {Array<{day: string, data: object}>} days metrics_daily documents.
 * @param {string} from First day to evaluate.
 * @param {string} to Last day to evaluate.
 * @return {object[]} One {day, level, reasons, notify} per night.
 */
function evaluateRange(days, from, to) {
  const byDay = new Map(days.map(({day, data}) => [day, dailySignals(data)]));
  const results = [];
  let state = null;
  for (let i = dayIndex(from); i <= dayIndex(to); i++) {
    const night = evaluateNight(byDay, dayKey(i), state);
    state = night.state;
    results.push({day: dayKey(i), level: night.level,
      reasons: night.reasons, notify: night.notify});
  }
  return results;
}

module.exports = {
  SIGNALS, dailySignals, scoreSignal, assess, evaluateNight, evaluateRange,
  dayKey, dayIndex,
};
