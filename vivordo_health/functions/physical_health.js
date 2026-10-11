"use strict";

// Physical Health: how fit and active someone has been over the last 4
// weeks (docs/scores.md §7). Measured against health guidelines rather than
// the person's own normal, because "healthy" shouldn't be relative.
// A wellness estimate, not a medical score.

const crypto = require("node:crypto");
const {isDeepStrictEqual} = require("node:util");
const {validDay} = require("./metrics_summary");
const {clockGap, usualClockTime} = require("./capacity");

const VERSION = 1;
const WINDOW_DAYS = 28;
const VO2_LOOKBACK_DAYS = 90;
const MIN_DAYS = 14; // days with any data before there's a score
const MIN_PARTS = 3; // of the 5 ingredients, so 1 or 2 can't decide it
const DAY_MS = 86400000;
const WEIGHTS = {activeMinutes: 30, movement: 15, strength: 20, cardio: 20,
  sleep: 15};
// Targets: WHO activity guidelines (150 min a week, strength twice a week),
// ~8,000 steps a day, 7–9 hours of sleep.
const ACTIVE_MINUTES_TARGET = 150;
const STEPS_TARGET = 8000;
const STRENGTH_TARGET = 2;
const STRENGTH = new RegExp("\\b(legs|arms|back|shoulders|chest|core|" +
  "strength|weights?|lift|lifting)\\b", "i");
// Median VO₂ max (ml/kg/min) by age decade, from published fitness norms
// (ACSM). Scored so the median is 60 and 20% above it is 100.
const VO2_MEDIAN = {
  male: [[30, 43], [40, 41], [50, 38], [60, 35], [70, 31], [Infinity, 28]],
  female: [[30, 37], [40, 35], [50, 32], [60, 29], [70, 26], [Infinity, 24]],
};

const finite = (value) => typeof value === "number" && Number.isFinite(value);
const clamp = (value) => Math.min(100, Math.max(0, value));
const round1 = (value) => value === null ? null :
  Math.round(value * 10 + 1e-9) / 10;
const sum = (values) => values.reduce((a, b) => a + b, 0);
const mean = (values) => values.length ? sum(values) / values.length : null;

/**
 * The median VO₂ max for an age and sex; "unspecified" averages the two.
 * @param {number} age Years.
 * @param {string|null} sex "female", "male" or "unspecified".
 * @return {number} ml/kg/min.
 */
function vo2Median(age, sex) {
  const lookup = (table) => table.find(([under]) => age < under)[1];
  if (sex === "male" || sex === "female") return lookup(VO2_MEDIAN[sex]);
  return (lookup(VO2_MEDIAN.male) + lookup(VO2_MEDIAN.female)) / 2;
}

/**
 * VO₂ max estimated without exercise: Jackson et al. (1990), from age,
 * sex, BMI and activity, averaged with Uth et al. (2004) when resting heart
 * rate is known (max HR from Tanaka: 208 − 0.7 × age).
 * @param {object} input {age, sex, heightCm, weightKg, weeklyActiveMinutes,
 *   restingHr}.
 * @return {number|null} ml/kg/min, or null without age, height and weight.
 */
function estimateVo2Max({age, sex, heightCm, weightKg, weeklyActiveMinutes,
  restingHr}) {
  if (!finite(age) || !finite(heightCm) || !finite(weightKg) ||
      heightCm <= 0 || weightKg <= 0) return null;
  const bmi = weightKg / (heightCm / 100) ** 2;
  // Self-rated activity (0–7) inferred from logged active minutes a week.
  const minutes = finite(weeklyActiveMinutes) ? weeklyActiveMinutes : 0;
  const activity = minutes < 15 ? 2 : minutes < 30 ? 4 : minutes < 60 ? 5 :
    minutes < 180 ? 6 : 7;
  const male = sex === "male" ? 1 : sex === "female" ? 0 : 0.5;
  const jackson = 56.363 + 1.921 * activity - 0.381 * age - 0.754 * bmi +
    10.987 * male;
  if (!finite(restingHr) || restingHr <= 30) return jackson;
  const uth = 15.3 * (208 - 0.7 * age) / restingHr;
  return (jackson + uth) / 2;
}

/**
 * Physical Health for the 28 days ending on a day.
 * @param {object} input
 * @param {object[]} input.days The window's days: {steps, exerciseMinutes,
 *   sleepHours, bedtimeMin, checkInSleep}; missing values null.
 * @param {object[]} input.workouts In-app workouts in the window:
 *   {name, category, exerciseCategories}.
 * @param {boolean} input.logsWorkouts Any in-app workout in the last 90
 *   days; strength is left out for people who don't log them here.
 * @param {object|null} input.vo2 Latest measured VO₂ max in 90 days:
 *   {value, source}.
 * @param {object} input.profile {age, sex, heightCm, weightKg}.
 * @param {number|null} input.restingHr Recent resting heart rate.
 * @return {object|null} The record, or null before 14 days of data.
 */
function computePhysicalHealth({days, workouts = [], logsWorkouts = false,
  vo2 = null, profile = {}, restingHr = null}) {
  const withData = days.filter((d) => [d.steps, d.exerciseMinutes,
    d.sleepHours, d.checkInSleep].some(finite));
  if (withData.length < MIN_DAYS) {
    return {score: null, label: "building", version: VERSION,
      daysOfData: withData.length};
  }
  const weeks = days.length / 7;

  const exercise = days.map((d) => d.exerciseMinutes).filter(finite);
  const weeklyActiveMinutes = exercise.length >= 7 ?
    sum(exercise) / weeks : null;
  const activeMinutes = weeklyActiveMinutes === null ? null :
    clamp(100 * weeklyActiveMinutes / ACTIVE_MINUTES_TARGET);

  const steps = days.map((d) => d.steps).filter((v) => finite(v) && v > 0);
  const avgSteps = steps.length >= 7 ? mean(steps) : null;
  const movement = avgSteps === null ? null :
    clamp(100 * avgSteps / STEPS_TARGET);

  const strengthSessions = workouts.filter((w) => STRENGTH.test(
      [w.name, w.category, ...(w.exerciseCategories || [])]
          .filter(Boolean).join(" ")) && !/cardio|run|walk|cycl|swim/i.test(
      [w.name, w.category].filter(Boolean).join(" "))).length;
  const strengthPerWeek = logsWorkouts ? strengthSessions / weeks : null;
  const strength = strengthPerWeek === null ? null :
    clamp(100 * strengthPerWeek / STRENGTH_TARGET);

  const age = profile.age;
  const estimated = vo2 ? null : estimateVo2Max({...profile,
    weeklyActiveMinutes, restingHr});
  const vo2Max = vo2?.value ?? estimated;
  const vo2Normal = finite(age) ? vo2Median(age, profile.sex) : null;
  const cardio = finite(vo2Max) && vo2Normal ?
    clamp(60 + 40 * (vo2Max / vo2Normal - 1) / 0.2) : null;

  // Sleep habits: 7–9 h most nights and a regular bedtime; from morning
  // check-ins ("How did you sleep?") when sleep isn't tracked.
  const nights = days.filter((d) => finite(d.sleepHours) && d.sleepHours > 0);
  let sleep = null;
  let sleepSource = null;
  let sleepHours = null;
  let onTimeShare = null;
  if (nights.length >= 7) {
    sleepHours = mean(nights.map((d) => d.sleepHours));
    const duration = mean(nights.map((d) => d.sleepHours < 7 ?
      clamp(100 - 40 * (7 - d.sleepHours)) : d.sleepHours > 9 ?
      clamp(100 - 25 * (d.sleepHours - 9)) : 100));
    const bedtimes = nights.map((d) => d.bedtimeMin).filter(finite);
    if (bedtimes.length >= 5) {
      const usual = usualClockTime(bedtimes);
      onTimeShare = bedtimes.filter((b) => clockGap(b, usual) <= 60).length /
        bedtimes.length;
      sleep = 0.7 * duration + 0.3 * 100 * onTimeShare;
    } else {
      sleep = duration;
    }
    sleepSource = "tracked";
  } else {
    const answers = days.map((d) => d.checkInSleep).filter(finite);
    if (answers.length >= 7) {
      sleep = clamp(mean(answers));
      sleepSource = "checkIn";
    }
  }

  const parts = {activeMinutes, movement, strength, cardio, sleep};
  let total = 0;
  let weight = 0;
  for (const [name, value] of Object.entries(parts)) {
    if (value === null) continue;
    total += WEIGHTS[name] * value;
    weight += WEIGHTS[name];
  }
  const present = Object.values(parts).filter((v) => v !== null).length;
  if (present < MIN_PARTS) {
    // Shown as "building" with what's still missing.
    return {score: null, label: "building", version: VERSION,
      daysOfData: withData.length,
      parts: Object.fromEntries(Object.entries(parts)
          .map(([k, v]) => [k, round1(v)]))};
  }
  const score = Math.round(total / weight);
  return {
    score,
    // Excellent needs most targets met, including above-average fitness.
    label: score >= 90 ? "excellent" : score >= 70 ? "good" :
      score >= 50 ? "fair" : "low",
    version: VERSION,
    daysOfData: withData.length,
    parts: Object.fromEntries(Object.entries(parts)
        .map(([k, v]) => [k, round1(v)])),
    details: {
      weeklyActiveMinutes: round1(weeklyActiveMinutes),
      avgSteps: avgSteps === null ? null : Math.round(avgSteps),
      strengthPerWeek: round1(strengthPerWeek),
      vo2Max: round1(finite(vo2Max) ? vo2Max : null),
      vo2Source: vo2 ? vo2.source : finite(estimated) ? "estimate" : null,
      vo2Normal: round1(vo2Normal),
      sleepHours: round1(sleepHours),
      sleepOnTimeShare: round1(onTimeShare),
      sleepSource,
    },
  };
}

/**
 * Whether a metrics_daily write changed anything Physical Health reads.
 * @param {object|undefined} before Previous document data.
 * @param {object|undefined} after New document data.
 * @return {boolean} True when it should be recalculated.
 */
function physicalInputsChanged(before, after) {
  const pick = (d) => [d?.steps?.sum, d?.exercise_time?.sum, d?.sleep?.avg,
    d?.vo2_max?.avg, d?.morning_check_in?.sleep, d?.weight?.avg];
  return !isDeepStrictEqual(pick(before), pick(after));
}

/**
 * Whether a user document write changed the profile fields Physical Health
 * reads (the VO₂ max estimate and its norms).
 * @param {object|undefined} before Previous user document data.
 * @param {object|undefined} after New user document data.
 * @return {boolean} True when it should be recalculated.
 */
function profileInputsChanged(before, after) {
  const pick = (d) => {
    const p = d?.preferences?.personalProfile;
    return [p?.heightCm, p?.weightKg, p?.birthYear, p?.sex];
  };
  return !isDeepStrictEqual(pick(before), pick(after));
}

const dayKey = (index) => new Date(index * DAY_MS).toISOString().slice(0, 10);
const dayIndex = (day) => Math.round(Date.parse(`${day}T00:00:00Z`) / DAY_MS);

/**
 * Recalculates and saves Physical Health for the 28 days ending on a day,
 * in users/{uid}/scores_daily/{day}.physical.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} day Day key.
 * @param {Function} timestamp Server timestamp factory.
 * @return {Promise<string>} Outcome.
 */
async function refreshPhysicalHealth(db, uid, day, timestamp) {
  if (!validDay(day)) return "ignored";
  const {FieldPath, Timestamp} = require("firebase-admin/firestore");
  const user = db.doc(`users/${uid}`);
  const end = dayIndex(day);
  const windowStart = dayKey(end - WINDOW_DAYS + 1);
  const lookback = dayKey(end - VO2_LOOKBACK_DAYS + 1);
  const [metrics, profileDoc, workouts, anyWorkout] = await Promise.all([
    user.collection("metrics_daily")
        .where(FieldPath.documentId(), ">=", lookback)
        .where(FieldPath.documentId(), "<=", day)
        .select("steps", "exercise_time", "sleep", "morning_check_in",
            "vo2_max", "resting_heart_rate", "weight")
        .get(),
    user.get(),
    user.collection("workouts")
        .where("exerciseGoalDay", ">=", windowStart)
        .where("exerciseGoalDay", "<=", day)
        .select("activityName", "activityCategory", "exercises")
        .get(),
    user.collection("workouts")
        .where("startedAt", ">=",
            Timestamp.fromMillis((end - VO2_LOOKBACK_DAYS) * DAY_MS))
        .limit(1).select().get(),
  ]);
  if (!profileDoc.exists) return "unavailable";

  const byDay = new Map(metrics.docs.map((d) => [d.id, d.data()]));
  const num = (v) => finite(v) ? v : null;
  const days = [];
  for (let i = end - WINDOW_DAYS + 1; i <= end; i++) {
    const d = byDay.get(dayKey(i));
    const bedtime = d?.sleep?.bedtime;
    const date = typeof bedtime?.toDate === "function" ? bedtime.toDate() :
      null;
    days.push({
      steps: num(d?.steps?.sum),
      exerciseMinutes: num(d?.exercise_time?.sum),
      sleepHours: num(d?.sleep?.avg),
      bedtimeMin: date ? date.getUTCHours() * 60 + date.getUTCMinutes() :
        null,
      checkInSleep: num(d?.morning_check_in?.sleep),
    });
  }
  // Latest measured VO₂ max (Apple Watch or Fitbit), latest weight and
  // resting heart rate, newest first.
  const newest = [...metrics.docs].sort((a, b) => b.id.localeCompare(a.id));
  const measured = newest.map((d) => d.data().vo2_max)
      .find((v) => finite(v?.avg) && v.estimated !== true);
  const weightKg = newest.map((d) => d.data().weight?.avg).find(finite);
  const restingHr = newest.slice(0, 14)
      .map((d) => d.data().resting_heart_rate?.avg).find(finite) ?? null;
  const stored = profileDoc.data()?.preferences?.personalProfile ?? {};
  const birthYear = num(stored.birthYear);
  const profile = {
    age: birthYear === null ? null :
      new Date(end * DAY_MS).getUTCFullYear() - birthYear,
    sex: stored.sex ?? null,
    heightCm: num(stored.heightCm),
    weightKg: num(stored.weightKg) ?? weightKg ?? null,
  };

  const next = computePhysicalHealth({
    days,
    workouts: workouts.docs.map((w) => ({
      name: w.get("activityName"), category: w.get("activityCategory"),
      exerciseCategories: (w.get("exercises") || [])
          .map((e) => e?.category).filter(Boolean),
    })),
    logsWorkouts: !anyWorkout.empty,
    vo2: measured ? {value: measured.avg,
      source: measured.source === "fitbit" ? "fitbit" : "apple_health"} :
      null,
    profile,
    restingHr,
  });

  const target = user.collection("scores_daily").doc(day);
  const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
  const deletion = db.doc(`account_deletion_jobs/${deletionId}`);
  return db.runTransaction(async (tx) => {
    const [owner, tombstone, existing] = await Promise.all([
      tx.get(user), tx.get(deletion), tx.get(target),
    ]);
    if (!owner.exists || tombstone.exists) return "unavailable";
    const old = existing.data()?.physical;
    const oldContent = old ? {...old} : null;
    if (oldContent) delete oldContent.computedAt;
    if (isDeepStrictEqual(next, oldContent)) return "unchanged";
    tx.set(target, {physical: {...next, computedAt: timestamp()}},
        {merge: true});
    return "written";
  });
}

module.exports = {
  VERSION, WEIGHTS, computePhysicalHealth, estimateVo2Max, vo2Median,
  physicalInputsChanged, profileInputsChanged, refreshPhysicalHealth,
};
