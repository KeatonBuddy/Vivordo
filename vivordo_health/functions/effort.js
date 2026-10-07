"use strict";

// Effort: what the day took (docs/scores.md §1, §3). Mental points from the
// day's events and completed priorities (the phone's day record,
// users/{uid}/effort_inputs/{day}), physical points from workouts and
// activity. Wellness estimate, not a medical score.

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {validDay} = require("./metrics_summary");

const VERSION = 1;
const MINUTE = 60000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const SHORT_GAP = 15 * MINUTE; // back-to-back, and what doesn't break a run
const BUMP_WINDOW = 30 * MINUTE;
const BUMP_AREA = 300; // rating-minutes per back-to-back (+0.5 points)
const UNKNOWN_RATING = 30;
const PRIORITY_RATING = {light: 20, moderate: 45, demanding: 75};
const UNTIMED_POINTS = {light: 2, moderate: 4, demanding: 6};
const AFTER_HOURS = 1.25;
const PHYSICAL_CAP = 25;
const LOCK_AFTER = 2 * DAY; // day records can arrive late
const MAX_ITEMS = 500;

const finite = (value) => typeof value === "number" && Number.isFinite(value);
// The epsilon keeps 15.75 (stored as 15.7499…) rounding up.
const round1 = (value) => Math.round(value * 10 + 1e-9) / 10;
const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};

// The continuous-run ramp integrated exactly: nothing for 60 minutes, then
// rising to +5 at 120 minutes (docs/calendar_load.md).
const rampArea = (t) => {
  const x = Math.min(60, Math.max(0, t - 60));
  return x * x / 120 + Math.max(0, t - 120);
};

/**
 * Hour-by-hour load, the same rules as the phone's
 * HourlyCalendarLoadCalculator (lib/src/services/hourly_calendar_load.dart,
 * v2), so Home's chart and the server agree (test/fixtures).
 * @param {object[]} items {id, start, end (ms), rating|null, always?}.
 *   `always` items count even after [asOf] (priorities ticked off early).
 * @param {number} from Hour-aligned start (ms).
 * @param {number} until End (ms).
 * @param {number} asOf Elapsed-time cutoff (ms).
 * @param {number} split A time (ms) whose later minutes are tallied apart.
 * @return {object[]} Per hour: {load, raw, rawAfter, occupied,
 *   occupiedAfter, unknown, transitions}.
 */
function hourlyLoads(items, from, until, asOf, split = Infinity) {
  const eligible = items.filter((e) => e.end > e.start &&
    (e.start < asOf || e.always)).sort((a, b) => a.start - b.start);
  const bumpEnd = new Map();
  for (const e of eligible) {
    const tight = eligible.some((p) => p.id !== e.id && p.end <= e.start &&
      e.start - p.end < SHORT_GAP);
    if (tight) {
      bumpEnd.set(e.id, e.start + Math.min(e.end - e.start, BUMP_WINDOW));
    }
  }
  const counts = (e, t) => e.start <= t && e.end > t && (t < asOf || e.always);
  const hours = [];
  for (let start = from; start < until; start += HOUR) {
    const stop = Math.min(start + HOUR, until);
    const points = new Set([start, stop]);
    for (const e of eligible) {
      for (const t of [e.start, e.end, bumpEnd.get(e.id), asOf, split]) {
        if (t > start && t < stop) points.add(t);
      }
    }
    const sorted = [...points].sort((a, b) => a - b);
    const hour = {raw: 0, rawAfter: 0, occupied: 0, occupiedAfter: 0,
      unknown: 0, transitions: 0};
    for (const e of eligible) {
      if (bumpEnd.has(e.id) && e.start >= start && e.start < stop &&
        (e.start < asOf || e.always)) hour.transitions++;
    }
    for (let i = 0; i < sorted.length - 1; i++) {
      const a = sorted[i];
      const minutes = (sorted[i + 1] - a) / MINUTE;
      const active = eligible.filter((e) => counts(e, a));
      if (!active.length) continue;
      const rating = Math.max(
          ...active.map((e) => e.rating ?? UNKNOWN_RATING));
      if (active.every((e) => e.rating == null)) hour.unknown += minutes;
      let tightRate = 0;
      for (const e of active) {
        const end = bumpEnd.get(e.id);
        if (end > a) {
          tightRate = Math.max(tightRate,
              BUMP_AREA / ((end - e.start) / MINUTE));
        }
      }
      let runStart = Math.min(...active.map((e) => e.start));
      for (const e of [...eligible].reverse()) {
        if (e.start < runStart && runStart - e.end < SHORT_GAP) {
          runStart = e.start;
        }
      }
      const run = (a - runStart) / MINUTE;
      const pressure = (active.length > 1 ? 10 : 0) + tightRate;
      const raw = minutes * (rating + pressure) +
        5 * (rampArea(run + minutes) - rampArea(run));
      hour.raw += raw;
      hour.occupied += minutes;
      if (a >= split) {
        hour.rawAfter += raw;
        hour.occupiedAfter += minutes;
      }
    }
    hour.load = Math.min(100, hour.raw / 60);
    hours.push(hour);
  }
  return hours;
}

const ms = (value) => typeof value?.toMillis === "function" ?
  value.toMillis() : finite(value) ? value : null;

/**
 * Intensity of an in-app workout in points per minute: light 0.1,
 * moderate 0.2, vigorous 0.35 (docs/scores.md §3).
 * @param {object} workout {name, category, exerciseCategories}.
 * @return {number} Points per minute.
 */
function workoutIntensity(workout) {
  const text = [workout.name, workout.category,
    ...(workout.exerciseCategories || [])].filter(Boolean).join(" ")
      .toLowerCase();
  const vigorous = new RegExp("\\b(run|running|sprint|hiit|interval|spin|" +
    "cycling|rowing|swim|boxing|crossfit)");
  if (vigorous.test(text)) return 0.35;
  if (/\b(walk|walking|yoga|stretch|mobility|pilates|cooldown)/.test(text)) {
    return 0.1;
  }
  return 0.2; // strength, sports, hikes and anything else
}

/**
 * A day's physical load in Effort points, uncapped: in-app workouts
 * (minutes × intensity) plus Health exercise minutes (× 0.2), or, with
 * neither, active calories above the usual (1 point per 50). Effort caps it
 * at PHYSICAL_CAP; Capacity compares the uncapped load with the person's
 * usual to spot a big day (docs/scores.md §4).
 * @param {object} input
 * @param {object[]} input.workouts {name, category, exerciseCategories,
 *   minutes}.
 * @param {number|null} input.healthMinutes Health exercise minutes outside
 *   in-app workouts.
 * @param {number|null} input.activeCalories The day's active calories.
 * @param {number|null} input.usualCalories Usual active calories.
 * @return {object} {points, source: "exercise" | "calories" | null}.
 */
function physicalLoad({workouts = [], healthMinutes = null,
  activeCalories = null, usualCalories = null}) {
  const workoutPoints = workouts.reduce((sum, w) =>
    sum + (finite(w.minutes) ? w.minutes : 0) * workoutIntensity(w), 0);
  const exercisePoints = (finite(healthMinutes) ? healthMinutes : 0) * 0.2;
  if (workoutPoints + exercisePoints > 0) {
    return {points: workoutPoints + exercisePoints, source: "exercise"};
  }
  if (finite(activeCalories) && finite(usualCalories)) {
    return {points: Math.max(0, activeCalories - usualCalories) / 50,
      source: "calories"};
  }
  return {points: 0, source: null};
}

/**
 * Effort for one day.
 * @param {object} input
 * @param {object} input.record The day record: {dayStart, dayEnd, wrapUpAt,
 *   events: [{start, end, rating, confidence}], priorities: [{start, end,
 *   effort, minutes, done}]}; times as ms or Timestamps.
 * @param {object[]} input.workouts In-app workouts that day: {name,
 *   category, exerciseCategories, minutes}.
 * @param {number|null} input.healthMinutes Health exercise minutes outside
 *   in-app workouts.
 * @param {number|null} input.activeCalories The day's active calories.
 * @param {number|null} input.usualCalories 90-day median active calories.
 * @param {number} input.asOf Now (ms): events count only once they happen.
 * @return {object|null} The Effort record, or null without a day record.
 */
function computeEffort({record, workouts = [], healthMinutes = null,
  activeCalories = null, usualCalories = null, asOf}) {
  const dayStart = ms(record?.dayStart);
  const dayEnd = ms(record?.dayEnd);
  if (dayStart === null || dayEnd === null) return null;
  const wrapUp = ms(record.wrapUpAt) ?? Infinity;
  const events = Array.isArray(record.events) ? record.events : [];
  const priorities = Array.isArray(record.priorities) ? record.priorities : [];

  const items = [];
  events.forEach((e, i) => {
    const start = ms(e.start);
    const end = ms(e.end);
    if (start === null || end === null) return;
    items.push({id: `e${i}`, start, end,
      rating: finite(e.rating) ? e.rating : null});
  });
  let untimedPoints = 0;
  const untimedAt = []; // [time, points] for the hour-by-hour totals
  let prioritiesDone = 0;
  priorities.forEach((p, i) => {
    if (p.done !== true) return;
    prioritiesDone++;
    const start = ms(p.start);
    const end = ms(p.end);
    if (start !== null && end !== null && end > start) {
      // Ticked off: counts in its slot even if that's still ahead.
      items.push({id: `p${i}`, start, end, always: true,
        rating: PRIORITY_RATING[p.effort] ?? PRIORITY_RATING.moderate});
    } else {
      const points = UNTIMED_POINTS[p.effort] ?? UNTIMED_POINTS.moderate;
      untimedPoints += points;
      untimedAt.push([ms(p.doneAt) ?? dayEnd - 1, points]);
    }
  });

  const hours = hourlyLoads(items, dayStart, dayEnd, Math.min(asOf, dayEnd),
      wrapUp);
  let scheduled = 0;
  const hourPoints = [];
  const totals = {busy: 0, after: 0, unknown: 0, transitions: 0};
  for (const h of hours) {
    // The hour's load (capped at 100), its after-hours share × 1.25.
    const afterShare = h.raw > 0 ? h.rawAfter / h.raw : 0;
    const points = h.load * (1 + (AFTER_HOURS - 1) * afterShare) / 10;
    scheduled += points;
    hourPoints.push(points);
    totals.busy += h.occupied;
    totals.after += h.occupiedAfter;
    totals.unknown += h.unknown;
    totals.transitions += h.transitions;
  }
  const mental = scheduled + untimedPoints;

  const hourOf = (t) => Math.min(hours.length - 1,
      Math.max(0, Math.floor((t - dayStart) / HOUR)));
  const workoutAt = workouts.map((w) => [ms(w.startedAt) ?? dayEnd - 1,
    (finite(w.minutes) ? w.minutes : 0) * workoutIntensity(w)]);
  const workoutPoints = workoutAt.reduce((sum, [, points]) => sum + points, 0);
  const exercisePoints = (finite(healthMinutes) ? healthMinutes : 0) * 0.2;
  const load = physicalLoad({workouts, healthMinutes, activeCalories,
    usualCalories});
  const physicalSource = load.source;
  const physical = Math.min(PHYSICAL_CAP, load.points);

  // Running total at the end of each hour of the day, for "usual by this
  // time of day" on Home. Workouts count at the hour they started (scaled
  // down with the cap), untimed priorities when ticked off; Health minutes
  // and calories, which have no time of day, at the end. The last value is
  // the day's total.
  const byHour = hours.map(() => 0);
  hourPoints.forEach((points, i) => byHour[i] += points);
  for (const [t, points] of untimedAt) byHour[hourOf(t)] += points;
  const scale = physicalSource === "exercise" ?
    physical / (workoutPoints + exercisePoints) : 0;
  for (const [t, points] of workoutAt) byHour[hourOf(t)] += points * scale;
  byHour[byHour.length - 1] += physical - workoutPoints * scale;
  for (let i = 1; i < byHour.length; i++) byHour[i] += byHour[i - 1];

  return {
    total: round1(mental + physical),
    mental: round1(mental),
    physical: round1(physical),
    // Uncapped, for the evening's "big day" note (docs/scores.md §4).
    physicalLoad: round1(load.points),
    physicalSource,
    version: VERSION,
    busyMinutes: Math.round(totals.busy),
    afterHoursMinutes: Math.round(totals.after),
    unknownMinutes: Math.round(totals.unknown),
    backToBack: totals.transitions,
    prioritiesDone,
    unfinishedPriorities: priorities.filter((p) => p.done !== true).length,
    byHour: byHour.map(round1),
  };
}

/**
 * Recalculates and saves a day's Effort in users/{uid}/scores_daily/{day},
 * then the next 3 days' Capacity (Recovery reads their load). Locked
 * 2 days after the day ends, since day records can arrive late.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {Function} timestamp Server timestamp factory.
 * @param {Date} now Current time.
 * @return {Promise<string>} Outcome.
 */
async function refreshEffort(db, uid, day, timestamp, now = new Date()) {
  if (!validDay(day)) return "ignored";
  const user = db.doc(`users/${uid}`);
  const record = (await user.collection("effort_inputs").doc(day).get()).data();
  const tooBig = (record?.events?.length ?? 0) > MAX_ITEMS ||
    (record?.priorities?.length ?? 0) > MAX_ITEMS;
  const dayStart = ms(record?.dayStart);
  const dayEnd = ms(record?.dayEnd);

  let effort = null;
  if (record && !tooBig && dayStart !== null && dayEnd !== null) {
    const {Timestamp, FieldPath} = require("firebase-admin/firestore");
    const workoutsSnap = await user.collection("workouts")
        .where("startedAt", ">=", Timestamp.fromMillis(dayStart))
        .where("startedAt", "<", Timestamp.fromMillis(dayEnd))
        .select("activityName", "activityCategory", "exercises",
            "durationMinutes", "startedAt")
        .get();
    const start = new Date(Date.parse(`${day}T00:00:00Z`) - 90 * DAY)
        .toISOString().slice(0, 10);
    const metrics = await user.collection("metrics_daily")
        .where(FieldPath.documentId(), ">=", start)
        .where(FieldPath.documentId(), "<=", day)
        .select("active_calories", "exercise_time")
        .get();
    const today = metrics.docs.find((d) => d.id === day)?.data();
    const pastCalories = metrics.docs.filter((d) => d.id < day)
        .map((d) => d.data().active_calories?.sum)
        .filter((v) => finite(v) && v > 0);
    effort = computeEffort({
      record,
      workouts: workoutsSnap.docs.map((d) => ({
        startedAt: d.get("startedAt"),
        name: d.get("activityName"),
        category: d.get("activityCategory"),
        exerciseCategories: (d.get("exercises") || [])
            .map((e) => e?.category).filter(Boolean),
        minutes: d.get("durationMinutes"),
      })),
      healthMinutes: today?.exercise_time?.healthSum ?? null,
      activeCalories: today?.active_calories?.sum ?? null,
      usualCalories: pastCalories.length >= 7 ? median(pastCalories) : null,
      asOf: now.getTime(),
    });
  }

  const target = user.collection("scores_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  const final = dayEnd !== null && dayEnd + LOCK_AFTER < now.getTime();
  const outcome = await db.runTransaction(async (tx) => {
    const [owner, tombstone, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    const old = existing.data()?.effort;
    if (old?.final) return "final";
    const next = effort && {...effort, final};
    const oldContent = old ? {...old} : null;
    if (oldContent) delete oldContent.computedAt;
    if (isDeepStrictEqual(next, oldContent)) return "unchanged";
    tx.set(target, {effort: next ? {...next, computedAt: timestamp()} : null},
        {merge: true});
    return "written";
  });
  if (outcome === "written") {
    // Recovery reads the last 3 days' load (a big day fades over three).
    const {refreshCapacity} = require("./capacity");
    for (let k = 1; k <= 3; k++) {
      const next = new Date(Date.parse(`${day}T00:00:00Z`) + k * DAY)
          .toISOString().slice(0, 10);
      await refreshCapacity(db, uid, next, timestamp, now);
    }
  }
  return outcome;
}

/**
 * Whether a metrics_daily write changed the activity Effort reads.
 * @param {object|undefined} before Previous document data.
 * @param {object|undefined} after New document data.
 * @return {boolean} True when Effort should be recalculated.
 */
function effortInputsChanged(before, after) {
  return before?.exercise_time?.healthSum !== after?.exercise_time?.healthSum ||
    before?.active_calories?.sum !== after?.active_calories?.sum;
}

module.exports = {
  VERSION, hourlyLoads, workoutIntensity, physicalLoad, computeEffort,
  refreshEffort, effortInputsChanged,
};
