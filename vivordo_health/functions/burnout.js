"use strict";

// Burnout early warning: compares the last 14 days of Capacity, Effort and
// Mood with the person's own normal (8 weeks, ending 2 weeks before the
// recent window). One area drifting is Watch; two agreeing is a Warning.
// Thresholds are starting values to tune against real histories; this is a
// wellness signal, not a diagnosis.

const {HRV_KINDS} = require("./hrv");
const {VERSION: EFFORT_VERSION} = require("./effort");

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
// The three headline signals decide the level (docs/scores.md §6); the
// drivers only explain it.
const SIGNALS = {
  capacity: {group: "capacity", headline: true, direction: -1, minChange: 5,
    label: "Capacity"},
  effort: {group: "effort", headline: true, direction: 1, minChange: 5,
    label: "Effort"},
  mood: {group: "mood", headline: true, direction: -1, minChange: 5,
    label: "Mood"},
  sleepHours: {group: "capacity", direction: -1, minChange: 1 / 3,
    label: "Sleep"},
  restingHeartRate: {group: "capacity", direction: 1, minChange: 2,
    label: "Resting heart rate", unit: " bpm"},
  hrv: {group: "capacity", direction: -1, minChange: 0.05, relative: true,
    label: "HRV", unit: " ms"},
  backToBack: {group: "effort", direction: 1, minChange: 1,
    label: "Back-to-backs", unit: " a day"},
  afterHoursMinutes: {group: "effort", direction: 1, minChange: 20,
    label: "After-hours time", unit: " min a day"},
};

/**
 * One day's signals; absent values are null.
 * @param {object|undefined} scores scores_daily document data.
 * @param {object|undefined} metrics metrics_daily document data.
 * @return {object} Signal values keyed like SIGNALS.
 */
function dailySignals(scores, metrics) {
  const num = (value) =>
    typeof value === "number" && Number.isFinite(value) ? value : null;
  // A Capacity still waiting for sleep is a weaker estimate: left out.
  const capacity = scores?.capacity?.provisional === false ?
    scores.capacity : null;
  const effort = scores?.effort?.version === EFFORT_VERSION ?
    scores.effort : null;
  return {
    capacity: num(capacity?.score),
    effort: num(effort?.total),
    mood: num(metrics?.mood?.avg),
    sleepHours: num(capacity?.sleepHours),
    restingHeartRate: capacity?.restingHrIgnored ? null :
      num(capacity?.restingHr),
    // By kind; assess() compares one kind only.
    hrv: num(capacity?.hrv) !== null && capacity.hrvKind ?
      {[capacity.hrvKind]: capacity.hrv} : null,
    backToBack: num(effort?.backToBack),
    afterHoursMinutes: num(effort?.afterHoursMinutes),
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
    // HRV kinds can't be compared, so use the preferred kind with enough
    // readings in both windows.
    for (const kind of name === "hrv" ? HRV_KINDS : [null]) {
      const recent = [];
      const baseline = [];
      for (let i = end - RECENT_DAYS - GAP_DAYS - BASELINE_DAYS + 1;
        i <= end; i++) {
        const day = byDay.get(dayKey(i))?.[name];
        const value = kind ? day?.[kind] : day;
        if (value == null) continue;
        if (i > end - RECENT_DAYS) recent.push(value);
        else if (i <= end - RECENT_DAYS - GAP_DAYS) baseline.push(value);
      }
      const result = scoreSignal(config, recent, baseline);
      if (!result) continue;
      signals[name] = {...result, group: config.group, ...kind && {kind}};
      break;
    }
  }
  // Each area's headline decides whether it's strained; drivers explain.
  const groups = {};
  for (const [name, signal] of Object.entries(signals)) {
    if (!SIGNALS[name].headline) continue;
    groups[signal.group] = {strained: signal.elevated, high: signal.high};
  }
  const list = Object.values(groups);
  const strained = list.filter((group) => group.strained);
  return {
    signals, groups,
    enoughData: list.length >= 1,
    strainedGroups: strained.length,
    // A big drift in one area backed by strain in another.
    acute: list.some((group) => group.high &&
      strained.some((other) => other !== group)),
    watch: strained.length >= 1,
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
 * What the app shows: each area's drift and the drivers behind it.
 * @param {object} signals Scored signals from assess().
 * @return {object} {areas: {capacity, effort, mood}, drivers: [...]}.
 */
function details(signals) {
  const pick = (signal) => signal && {
    usual: Math.round(signal.usual * 10) / 10,
    recent: Math.round(signal.recent * 10) / 10,
    worseDays: signal.worseDays, days: signal.days,
    elevated: signal.elevated, high: signal.high,
    score: Math.round(signal.score * 10) / 10,
  };
  const areas = {};
  for (const name of ["capacity", "effort", "mood"]) {
    areas[name] = pick(signals[name]) ?? null;
  }
  const drivers = Object.entries(signals)
      .filter(([name, signal]) => !SIGNALS[name].headline && signal.elevated)
      .sort(([, a], [, b]) => b.score - a.score)
      .map(([name, signal]) => ({name, ...pick(signal)}));
  return {areas, drivers};
}

/**
 * Days so far towards the ~6 weeks a first check needs: the days since the
 * earliest Capacity, Effort or Mood in the 12-week window.
 * @param {Map<string, object>} byDay Day key -> dailySignals result.
 * @param {string} today Day key being evaluated.
 * @return {number} Days of history.
 */
function learningDays(byDay, today) {
  const end = dayIndex(today);
  const window = RECENT_DAYS + GAP_DAYS + BASELINE_DAYS;
  for (let i = end - window + 1; i <= end; i++) {
    const day = byDay.get(dayKey(i));
    if (day && ["capacity", "effort", "mood"].some((k) => day[k] != null)) {
      return end - i + 1;
    }
  }
  return 0;
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
      learningDays: learningDays(byDay, today), since: null,
      ...details(night.signals),
      state: {...state, strainedDays: 0, calmDays: 0, level: "learning",
        since: null}};
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
  // When the current level started, for "Signs of a slide for 10 days".
  const since = level === state.level ? state.since ?? today : today;
  return {
    level, reasons: reasons(night.signals), notify, since,
    learningDays: null, ...details(night.signals),
    state: {...state, level, since,
      lastNotified: notify ? today : state.lastNotified},
  };
}

/**
 * Replays nightly evaluations over a day range (tests).
 * @param {Array<{day: string, scores: object, metrics: object}>} days
 *   scores_daily and metrics_daily data per day.
 * @param {string} from First day to evaluate.
 * @param {string} to Last day to evaluate.
 * @return {object[]} One {day, level, reasons, notify} per night.
 */
function evaluateRange(days, from, to) {
  const byDay = new Map(days.map(({day, scores, metrics}) =>
    [day, dailySignals(scores, metrics)]));
  const results = [];
  let state = null;
  for (let i = dayIndex(from); i <= dayIndex(to); i++) {
    const night = evaluateNight(byDay, dayKey(i), state);
    state = night.state;
    results.push({day: dayKey(i), level: night.level,
      reasons: night.reasons, notify: night.notify, since: night.since,
      areas: night.areas, drivers: night.drivers,
      learningDays: night.learningDays});
  }
  return results;
}

const VERSION = 1;

/**
 * Evaluates a day that has just ended and saves the result in
 * users/{uid}/scores_daily/{day}.burnout, carrying the previous night's
 * state. Runs once per day: a day already evaluated is left alone, so a
 * retry never sends a second notification.
 * @param {object} db Admin Firestore instance.
 * @param {object} messaging Admin Messaging instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key that just ended.
 * @param {Function} timestamp Server timestamp factory.
 * @return {Promise<string>} Outcome.
 */
async function refreshBurnout(db, messaging, uid, day, timestamp) {
  const crypto = require("node:crypto");
  const {FieldPath} = require("firebase-admin/firestore");
  const user = db.doc(`users/${uid}`);
  const window = RECENT_DAYS + GAP_DAYS + BASELINE_DAYS;
  const start = dayKey(dayIndex(day) - window);
  const range = (name, ...fields) => user.collection(name)
      .where(FieldPath.documentId(), ">=", start)
      .where(FieldPath.documentId(), "<=", day)
      .select(...fields).get();
  const [scores, metrics] = await Promise.all([
    range("scores_daily", "capacity", "effort", "burnout"),
    range("metrics_daily", "mood"),
  ]);
  const scoresByDay = new Map(scores.docs.map((d) => [d.id, d.data()]));
  const byDay = new Map();
  for (let i = dayIndex(start); i <= dayIndex(day); i++) {
    const key = dayKey(i);
    const mood = metrics.docs.find((d) => d.id === key)?.data();
    byDay.set(key, dailySignals(scoresByDay.get(key), mood));
  }
  const previous = scoresByDay.get(dayKey(dayIndex(day) - 1))?.burnout?.state;
  const night = evaluateNight(byDay, day, previous ?? null);

  const target = user.collection("scores_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  const outcome = await db.runTransaction(async (tx) => {
    const [owner, tombstone, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    if (existing.data()?.burnout) return "done";
    tx.set(target, {burnout: {
      version: VERSION, level: night.level, since: night.since,
      areas: night.areas, drivers: night.drivers,
      learningDays: night.learningDays, notified: night.notify,
      state: night.state, computedAt: timestamp(),
    }}, {merge: true});
    return night.notify ? "notify" : "written";
  });
  if (outcome === "notify") await notifyWarning(user, messaging, night.areas);
  return outcome;
}

/**
 * "Lower energy and heavier days than usual. ..." from the strained areas.
 * @param {object} areas The night's areas.
 * @return {string} Notification body.
 */
function warningBody(areas) {
  const words = [
    areas?.capacity?.elevated && "lower energy",
    areas?.effort?.elevated && "heavier days",
    areas?.mood?.elevated && "lower mood",
  ].filter(Boolean);
  const list = words.length > 1 ?
    `${words.slice(0, -1).join(", ")} and ${words.at(-1)}` : words[0] ??
    "a change";
  return `${list[0].toUpperCase()}${list.slice(1)} than usual. ` +
    "Take a look at what's changed.";
}

/**
 * The one push sent when a Warning starts.
 * @param {object} user User document reference.
 * @param {object} messaging Admin Messaging instance.
 * @param {object} areas The night's areas, to say which ones drifted.
 */
async function notifyWarning(user, messaging, areas) {
  const [profile, tokens] = await Promise.all([
    user.get(), user.collection("notification_tokens").get(),
  ]);
  if (profile.data()?.preferences?.notificationsEnabled === false) return;
  const valid = tokens.docs.filter((d) =>
    typeof d.get("token") === "string" && d.get("token"));
  if (!valid.length) return;
  const response = await messaging.sendEachForMulticast({
    tokens: valid.map((d) => d.get("token")),
    notification: {
      title: "Your last two weeks look like a slide",
      body: warningBody(areas),
    },
    data: {screen: "calendar", type: "burnout_warning"}, // opens My Day
    apns: {payload: {aps: {sound: "default"}}},
  });
  await Promise.all(response.responses.map((result, i) =>
    !result.success && ["messaging/registration-token-not-registered",
      "messaging/invalid-registration-token"].includes(result.error?.code) ?
      valid[i].ref.delete() : null));
}

module.exports = {
  VERSION, refreshBurnout, details, learningDays, warningBody,
  SIGNALS, dailySignals, scoreSignal, assess, evaluateNight, evaluateRange,
  dayKey, dayIndex,
};
