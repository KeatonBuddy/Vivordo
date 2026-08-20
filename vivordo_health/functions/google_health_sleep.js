"use strict";

const SLEEPING_STAGE_TYPES = new Set(["LIGHT", "DEEP", "REM", "ASLEEP"]);
const DETAILED_STAGE_TYPES = new Set(["AWAKE", "LIGHT", "DEEP", "REM"]);

const finiteNumber = (value) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
};

const parsedDate = (value) => {
  const milliseconds = Date.parse(value);
  return Number.isFinite(milliseconds) ? new Date(milliseconds) : null;
};

const durationMinutes = (startTime, endTime) => {
  const start = Date.parse(startTime);
  const end = Date.parse(endTime);
  return Number.isFinite(start) && Number.isFinite(end) && end > start ?
    (end - start) / 60000 : 0;
};

const civilDateKey = (value) => {
  const date = value?.date || value;
  if (!date?.year || !date?.month || !date?.day) return null;
  return [
    String(date.year).padStart(4, "0"),
    String(date.month).padStart(2, "0"),
    String(date.day).padStart(2, "0"),
  ].join("-");
};

const offsetSeconds = (value) => {
  if (typeof value !== "string" || !value.endsWith("s")) return 0;
  return finiteNumber(value.slice(0, -1)) || 0;
};

const sleepDayKey = (sleep) => {
  const civilKey = civilDateKey(sleep?.interval?.civilEndTime);
  if (civilKey) return civilKey;
  const end = parsedDate(sleep?.interval?.endTime);
  if (!end) return null;
  const localEnd = new Date(
      end.getTime() + offsetSeconds(sleep.interval.endUtcOffset) * 1000,
  );
  return localEnd.toISOString().slice(0, 10);
};

const sleepMinutes = (sleep) => {
  const summaryMinutes = finiteNumber(sleep?.summary?.minutesAsleep);
  if (summaryMinutes !== null) return summaryMinutes;
  return (sleep?.stages || []).reduce((total, stage) => {
    if (!SLEEPING_STAGE_TYPES.has(stage.type)) return total;
    return total + durationMinutes(stage.startTime, stage.endTime);
  }, 0);
};

const detailedStageMinutes = (sleep) => {
  if (sleep?.type !== "STAGES") return {};
  const fromSummary = {};
  for (const stage of sleep.summary?.stagesSummary || []) {
    if (!DETAILED_STAGE_TYPES.has(stage.type)) continue;
    const minutes = finiteNumber(stage.minutes);
    if (minutes !== null && minutes >= 0) fromSummary[stage.type] = minutes;
  }
  if (Object.keys(fromSummary).length > 0) return fromSummary;

  const fromIntervals = {};
  for (const stage of sleep.stages || []) {
    if (!DETAILED_STAGE_TYPES.has(stage.type)) continue;
    fromIntervals[stage.type] = (fromIntervals[stage.type] || 0) +
      durationMinutes(stage.startTime, stage.endTime);
  }
  return fromIntervals;
};

/**
 * Converts Google Health Fitbit sleep sessions into Vivordo daily summaries.
 *
 * @param {Object[]} dataPoints Google Health sleep data points.
 * @return {Object<string, Object>} Sleep summaries keyed by wake-up day.
 */
function normalizeGoogleHealthSleep(dataPoints) {
  const totals = {};
  for (const point of dataPoints || []) {
    const sleep = point?.sleep;
    const day = sleepDayKey(sleep);
    const minutes = sleepMinutes(sleep);
    if (!day || minutes <= 0) continue;
    if (!totals[day]) {
      totals[day] = {
        minutes: 0,
        minutesInSleepPeriod: 0,
        stages: {awake: 0, core: 0, deep: 0, rem: 0},
        hasDetailedStages: false,
        bedtime: null,
        wakeTime: null,
      };
    }
    const total = totals[day];
    total.minutes += minutes;
    const periodMinutes = finiteNumber(sleep.summary?.minutesInSleepPeriod) ??
      durationMinutes(sleep.interval?.startTime, sleep.interval?.endTime);
    total.minutesInSleepPeriod += Math.max(periodMinutes, minutes);

    const stages = detailedStageMinutes(sleep);
    if (Object.keys(stages).length > 0) total.hasDetailedStages = true;
    total.stages.awake += stages.AWAKE || 0;
    total.stages.core += stages.LIGHT || 0;
    total.stages.deep += stages.DEEP || 0;
    total.stages.rem += stages.REM || 0;

    const start = parsedDate(sleep.interval?.startTime);
    const end = parsedDate(sleep.interval?.endTime);
    if (start && (!total.bedtime || start < total.bedtime)) {
      total.bedtime = start;
    }
    if (end && (!total.wakeTime || end > total.wakeTime)) {
      total.wakeTime = end;
    }
  }

  const normalized = {};
  for (const [day, total] of Object.entries(totals)) {
    const result = {
      minutes: total.minutes,
      bedtime: total.bedtime,
      wakeTime: total.wakeTime,
    };
    if (total.hasDetailedStages) result.stages = total.stages;
    if (total.minutesInSleepPeriod > 0) {
      result.efficiency = Math.max(0, Math.min(
          100,
          total.minutes / total.minutesInSleepPeriod * 100,
      ));
    }
    normalized[day] = result;
  }
  return normalized;
}

module.exports = {
  normalizeGoogleHealthSleep,
  sleepDayKey,
  sleepMinutes,
};
