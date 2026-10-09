"use strict";

// Daily budget for the AI callables (assistant, aiTask, classifyPlanItems).
const DAILY_CALL_LIMIT = 200; // a heavy chat day is well under 100 calls

/**
 * Next daily usage record, or null when today's limit is spent.
 *
 * @param {Object|undefined} current Stored {day, count}.
 * @param {string} day Today's UTC day key (YYYY-MM-DD).
 * @param {number} limit Calls allowed per day.
 * @return {{day: string, count: number}|null}
 */
function nextUsage(current, day, limit = DAILY_CALL_LIMIT) {
  const count = current?.day === day ? Number(current.count) || 0 : 0;
  return count >= limit ? null : {day, count: count + 1};
}

module.exports = {nextUsage, DAILY_CALL_LIMIT};
