"use strict";

const WHOOP_CLOUD_SOURCE = "whoop";
const WHOOP_BLE_SOURCE = "whoop_ble";
const HEART_RATE_FALLBACK_ORDER = [
  "wearable_ble",
  "fitbit_ble",
  "apple_health",
];

/**
 * Builds a source-aware cleanup plan for one metrics_daily document.
 * The caller converts deletePaths to Firestore FieldValue.delete() values.
 *
 * @param {object} data Existing metrics document.
 * @return {{deletePaths: string[], setFields: object, changed: boolean,
 *   removedSleep: boolean, removedHeartRate: boolean}}
 */
function whoopDeletionPlan(data = {}) {
  const deletePaths = [];
  const setFields = {};
  const removedSleep = data.sleep?.source === WHOOP_CLOUD_SOURCE;
  const sources = data.heart_rate_sources || {};
  const removedHeartRate = Boolean(sources[WHOOP_BLE_SOURCE]) ||
    data.heart_rate?.source === WHOOP_BLE_SOURCE;

  if (removedSleep) deletePaths.push("sleep");

  if (sources[WHOOP_BLE_SOURCE]) {
    const remainingKeys = Object.keys(sources)
        .filter((key) => key !== WHOOP_BLE_SOURCE);
    deletePaths.push(remainingKeys.length === 0 ?
      "heart_rate_sources" :
      `heart_rate_sources.${WHOOP_BLE_SOURCE}`);
  }

  if (data.heart_rate?.source === WHOOP_BLE_SOURCE) {
    const fallbackKey = HEART_RATE_FALLBACK_ORDER
        .find((key) => sources[key] && key !== WHOOP_BLE_SOURCE);
    if (fallbackKey) {
      setFields.heart_rate = {...sources[fallbackKey]};
    } else {
      deletePaths.push("heart_rate");
    }
  }

  // These outputs can depend on WHOOP sleep or heart rate but legacy records
  // do not yet carry complete input provenance. Invalidate replaceable output
  // instead of leaving a score derived from data the member asked to delete.
  if (removedSleep || removedHeartRate) {
    if (data.stress !== undefined) deletePaths.push("stress");
    if (data.wellness !== undefined) deletePaths.push("wellness");
  }
  if (removedHeartRate && data.heart_health !== undefined) {
    deletePaths.push("heart_health");
  }

  return {
    deletePaths: [...new Set(deletePaths)],
    setFields,
    changed: removedSleep || removedHeartRate,
    removedSleep,
    removedHeartRate,
  };
}

module.exports = {
  whoopDeletionPlan,
};
