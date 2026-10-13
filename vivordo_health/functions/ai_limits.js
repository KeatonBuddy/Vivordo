"use strict";

// Daily budgets for the AI callables. Chat has its own, so a heavy chat day
// doesn't stop workout analysis or check-in questions (aiTask), and event
// sorting (classifyPlanItems) has a third.
const DAILY_CALL_LIMIT = 200;
const DAILY_CHAT_LIMIT = 100; // Vivordo AI messages a day, a fair-use cap

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

module.exports = {nextUsage, DAILY_CALL_LIMIT, DAILY_CHAT_LIMIT};
