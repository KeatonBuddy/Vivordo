"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  activityGoalsFromUserData,
  calculateActivityScore,
} = require("../activity_score");

const score = (values = {}) => calculateActivityScore({
  stepsGoal: 10000,
  exerciseMinutesGoal: 40,
  activeCaloriesGoal: 700,
  ...values,
});

test("returns null when every activity signal is unavailable", () => {
  assert.equal(score(), null);
});

test("redistributes unavailable signal weights", () => {
  const result = score({exerciseMinutes: 32, activeCalories: 420});
  assert.equal(result.score, 75);
  assert.equal(result.availableSignals, 2);
});

test("retains recorded zeroes", () => {
  const result = score({
    steps: 0,
    exerciseMinutes: 40,
    activeCalories: 700,
  });
  assert.equal(result.score, 80);
  assert.equal(result.availableSignals, 3);
});

test("uses stored goals and falls back invalid values", () => {
  assert.deepEqual(activityGoalsFromUserData({
    preferences: {
      activityGoals: {
        steps: 8000,
        exerciseMinutes: 30,
        activeCalories: 0,
      },
    },
  }), {
    steps: 8000,
    exerciseMinutes: 30,
    activeCalories: 700,
  });
});
