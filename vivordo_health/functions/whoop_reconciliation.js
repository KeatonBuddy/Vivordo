"use strict";

/**
 * Resolves a WHOOP timestamp to its recorded local calendar day.
 *
 * @param {string} timestamp ISO timestamp.
 * @param {string} timezoneOffset WHOOP timezone offset.
 * @return {?string}
 */
function whoopDateKey(timestamp, timezoneOffset = "+00:00") {
  const milliseconds = Date.parse(timestamp);
  if (!Number.isFinite(milliseconds)) return null;
  const match = /^([+-])(\d{2}):(\d{2})$/.exec(timezoneOffset || "");
  const direction = match?.[1] === "-" ? -1 : 1;
  const offsetMinutes = match ?
    direction * (Number(match[2]) * 60 + Number(match[3])) : 0;
  return new Date(milliseconds + offsetMinutes * 60000)
      .toISOString().slice(0, 10);
}

/**
 * Shifts an ISO date key without applying the server timezone.
 *
 * @param {string} dateKey ISO local date.
 * @param {number} days Signed day offset.
 * @return {?string}
 */
function shiftDateKey(dateKey, days) {
  const parsed = new Date(`${dateKey}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime())) return null;
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}

/**
 * Returns the fully-covered local dates that may be reconciled.
 * Morning and overnight calls preserve the current day while WHOOP may still
 * be scoring it. The midday safety call may reconcile it.
 *
 * @param {object} options Reconciliation window.
 * @return {string[]}
 */
function whoopReconciliationDays(options) {
  const daysBack = Math.max(1, Math.trunc(Number(options.daysBack) || 1));
  const firstOffset = options.includeCurrentDay === true ? 0 : 1;
  const days = [];
  for (let offset = firstOffset; offset < daysBack; offset += 1) {
    const day = shiftDateKey(options.localDate, -offset);
    if (day) days.push(day);
  }
  return days;
}

/**
 * Includes scored and unscored records. An unscored record is pending, not
 * deleted, and must protect the existing Firestore sleep value.
 *
 * @param {object[]} sleeps Raw WHOOP sleep records.
 * @return {Set<string>}
 */
function whoopPresentSleepDays(sleeps) {
  const days = new Set();
  for (const sleep of sleeps) {
    const day = whoopDateKey(sleep?.end, sleep?.timezone_offset);
    if (day) days.add(day);
  }
  return days;
}

/**
 * Determines whether an existing daily sleep field is a stale WHOOP value.
 *
 * @param {?object} existingSleep Existing Firestore sleep field.
 * @param {boolean} returnedForDay Whether WHOOP returned that wake day.
 * @return {boolean}
 */
function shouldDeleteWhoopSleep(existingSleep, returnedForDay) {
  return returnedForDay !== true && existingSleep?.source === "whoop";
}

/**
 * Whether a completed WHOOP fetch may clear the nights it did not return.
 *
 * A response carrying no sleep at all is ambiguous: it looks identical
 * whether the member truly logged no sleep in the window or the fetch could
 * not see it — an upstream incident answering 200 with an empty page, or a
 * token that is still valid but no longer scoped for sleep. Reconciling
 * against that deletes every WHOOP night in the window, which for a manual
 * refresh is the full requested history rather than the two days a scheduled
 * sync looks at.
 *
 * A response containing at least one night is trusted: sleep is readable, so
 * a night absent from it really was removed on WHOOP's side.
 *
 * A failed fetch never reaches here — it throws before reconciliation.
 *
 * @param {Set<string>} presentDays Wake days the fetch returned.
 * @return {boolean}
 */
function whoopFetchMayClearSleep(presentDays) {
  return (presentDays?.size ?? 0) > 0;
}

module.exports = {
  shouldDeleteWhoopSleep,
  whoopDateKey,
  whoopFetchMayClearSleep,
  whoopPresentSleepDays,
  whoopReconciliationDays,
};
