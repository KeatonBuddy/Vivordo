"use strict";

const HEART_HEALTH_BASELINE_WINDOW_DAYS = 28;
const HEART_HEALTH_MINIMUM_BASELINE_DAYS = 7;

const valid = (value) => Number.isFinite(value) && value > 0;

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ?
    sorted[middle] :
    (sorted[middle - 1] + sorted[middle]) / 2;
};

const personalizedScore = ({
  current,
  history,
  lowerIsBetter,
  minimumScale,
  pointsPerDeviation,
}) => {
  const values = history.filter(valid);
  if (!valid(current) || values.length < HEART_HEALTH_MINIMUM_BASELINE_DAYS) {
    return null;
  }
  const baseline = median(values);
  const deviation = median(values.map((value) => Math.abs(value - baseline)));
  const scale = Math.max(deviation * 1.4826, minimumScale);
  const standardizedDifference = (current - baseline) / scale;
  const direction = lowerIsBetter ? -1 : 1;
  return Math.max(0, Math.min(
      100,
      80 + standardizedDifference * direction * pointsPerDeviation,
  ));
};

/**
 * Calculates personalized Heart Health while redistributing missing weights.
 *
 * @param {Object} current Current resting HR, SDNN HRV, and quiet HR.
 * @param {Object[]} history Up to 28 earlier daily signal objects.
 * @return {Object} Score, component scores, baseline state, and confidence.
 */
function calculateHeartHealthScore(current, history) {
  const restingHistory = history.map((day) => day.restingHeartRate);
  const hrvHistory = history.map((day) => day.hrvSdnn);
  const quietHistory = history.map((day) => day.quietHeartRate);
  const restingHeartRateScore = personalizedScore({
    current: current.restingHeartRate,
    history: restingHistory,
    lowerIsBetter: true,
    minimumScale: 3,
    pointsPerDeviation: 12,
  });
  const hrvScore = personalizedScore({
    current: current.hrvSdnn,
    history: hrvHistory,
    lowerIsBetter: false,
    minimumScale: 5,
    pointsPerDeviation: 10,
  });
  const quietHeartRateScore = personalizedScore({
    current: current.quietHeartRate,
    history: quietHistory,
    lowerIsBetter: true,
    minimumScale: 3,
    pointsPerDeviation: 10,
  });
  const components = [
    {score: restingHeartRateScore, weight: 0.50},
    {score: hrvScore, weight: 0.30},
    {score: quietHeartRateScore, weight: 0.20},
  ];
  const scored = components.filter((component) => component.score !== null);
  const availableWeight = scored.reduce(
      (total, component) => total + component.weight,
      0,
  );
  const score = availableWeight === 0 ? null : scored.reduce(
      (total, component) => total + component.score * component.weight,
      0,
  ) / availableWeight;
  const availableSignals = [
    current.restingHeartRate,
    current.hrvSdnn,
    current.quietHeartRate,
  ].filter(valid).length;
  const baselineCounts = [
    restingHeartRateScore === null ? null : restingHistory.filter(valid).length,
    hrvScore === null ? null : hrvHistory.filter(valid).length,
    quietHeartRateScore === null ? null : quietHistory.filter(valid).length,
  ].filter((value) => value !== null);
  const allCounts = [restingHistory, hrvHistory, quietHistory]
      .map((values) => values.filter(valid).length);
  const baselineDays = baselineCounts.length > 0 ?
    Math.min(...baselineCounts) : Math.max(...allCounts);
  const scoredSignals = scored.length;
  const confidence = scoredSignals === 3 && baselineDays >= 14 ?
    "high" : scoredSignals >= 2 || (scoredSignals === 1 && baselineDays >= 14) ?
    "medium" : "low";

  return {
    score,
    restingHeartRateScore,
    hrvScore,
    quietHeartRateScore,
    availableSignals,
    scoredSignals,
    baselineDays,
    confidence,
    isBuildingBaseline: availableSignals > 0 && score === null,
  };
}

module.exports = {
  calculateHeartHealthScore,
  HEART_HEALTH_BASELINE_WINDOW_DAYS,
  HEART_HEALTH_MINIMUM_BASELINE_DAYS,
};
