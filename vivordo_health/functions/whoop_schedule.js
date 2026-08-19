"use strict";

/**
 * Resolves the user's local date and the sleep-sync slot for a UTC instant.
 * The offset is supplied by the signed-in device because the app already uses
 * the device's local day for metrics_daily document IDs.
 *
 * @param {number} nowMs UTC milliseconds.
 * @param {number} timezoneOffsetMinutes Local time minus UTC, in minutes.
 * @return {{localDate: string, sleepSlot: string}}
 */
function whoopLocalSlot(nowMs, timezoneOffsetMinutes) {
  const rawOffset = Number(timezoneOffsetMinutes);
  const offset = Number.isFinite(rawOffset) ?
    Math.max(-14 * 60, Math.min(14 * 60, Math.trunc(rawOffset))) : 0;
  const local = new Date(nowMs + offset * 60 * 1000);
  const hour = local.getUTCHours();
  return {
    localDate: local.toISOString().slice(0, 10),
    sleepSlot: hour < 4 ? "overnight" : hour < 12 ? "morning" : "midday",
  };
}

/**
 * Determines which WHOOP endpoints are due before active leases are applied.
 *
 * @param {object} options Scheduling inputs.
 * @return {{sleep: boolean, localDate: string, sleepSlot: string}}
 */
function dueWhoopEndpoints(options) {
  const nowMs = Number(options.nowMs);
  const force = options.force === true;
  const {localDate, sleepSlot} = whoopLocalSlot(
      nowMs,
      options.timezoneOffsetMinutes,
  );
  const lastSleepDate = sleepSlot === "morning" ?
    options.lastSleepMorningDate : options.lastSleepMiddayDate;
  return {
    sleep: force || (sleepSlot !== "overnight" &&
      lastSleepDate !== localDate),
    localDate,
    sleepSlot,
  };
}

/**
 * Returns whether a WHOOP failure proves the stored authorization can no
 * longer be used. Transient availability and rate-limit errors must leave the
 * connection intact.
 *
 * @param {string} code Firebase Functions error code.
 * @return {boolean}
 */
function isWhoopAuthorizationFailureCode(code) {
  return code === "unauthenticated" || code === "failed-precondition";
}

module.exports = {
  dueWhoopEndpoints,
  isWhoopAuthorizationFailureCode,
  whoopLocalSlot,
};
