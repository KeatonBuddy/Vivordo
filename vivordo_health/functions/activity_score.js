"use strict";

const DEFAULT_ACTIVITY_GOALS = Object.freeze({
  steps: 10000,
  exerciseMinutes: 40,
  activeCalories: 700,
});

/**
 * Reads validated activity goals from a Firestore user document.
 *
 * @param {Object|undefined} userData Firestore user data.
 * @return {{steps: number, exerciseMinutes: number, activeCalories: number}}
 */
function activityGoalsFromUserData(userData) {
  const stored = userData?.preferences?.activityGoals || {};
  const positive = (value, fallback) =>
    Number.isFinite(Number(value)) && Number(value) > 0 ?
      Number(value) : fallback;
  return {
    steps: positive(stored.steps, DEFAULT_ACTIVITY_GOALS.steps),
    exerciseMinutes: positive(
        stored.exerciseMinutes,
        DEFAULT_ACTIVITY_GOALS.exerciseMinutes,
    ),
    activeCalories: positive(
        stored.activeCalories,
        DEFAULT_ACTIVITY_GOALS.activeCalories,
    ),
  };
}

/**
 * Calculates activity while excluding unavailable signals and retaining zeroes.
 *
 * @param {Object} values Activity values and goals.
 * @return {{score: number, availableSignals: number}|null} Score result.
 */
function calculateActivityScore(values) {
  const normalized = (value, goal) => {
    if (!Number.isFinite(value) || !Number.isFinite(goal) || goal <= 0) {
      return null;
    }
    return Math.max(0, Math.min(100, value / goal * 100));
  };
  const movement = normalized(values.steps, values.stepsGoal);
  const exercise = normalized(
      values.exerciseMinutes,
      values.exerciseMinutesGoal,
  );
  const exertion = normalized(
      values.activeCalories,
      values.activeCaloriesGoal,
  );
  const movementSignals = [movement, exercise]
      .filter((value) => value !== null)
      .sort((a, b) => b - a);

  let weightedScore = 0;
  let availableWeight = 0;
  if (movementSignals.length > 0) {
    weightedScore += movementSignals[0] * 0.60;
    availableWeight += 0.60;
  }
  if (movementSignals.length > 1) {
    weightedScore += movementSignals[1] * 0.20;
    availableWeight += 0.20;
  }
  if (exertion !== null) {
    weightedScore += exertion * 0.20;
    availableWeight += 0.20;
  }
  if (availableWeight === 0) return null;

  return {
    score: Math.max(0, Math.min(100, weightedScore / availableWeight)),
    availableSignals: [movement, exercise, exertion]
        .filter((value) => value !== null).length,
  };
}

module.exports = {
  activityGoalsFromUserData,
  calculateActivityScore,
  DEFAULT_ACTIVITY_GOALS,
};
