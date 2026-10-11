"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {sendDayRecordPushes} = require("../day_record_push");

test("sends a silent push per device and removes dead tokens", async () => {
  const deleted = [];
  const doc = (token) => ({get: () => token, ref: {delete: async () => deleted.push(token)}});
  const queried = [];
  const db = {collectionGroup: () => ({
    where: (field, op, hour) => {
      queried.push([field, op, hour]);
      return {select: () => ({get: async () => ({docs: [doc("good"), doc("dead"), doc("")]})})};
    },
  })};
  let message;
  const messaging = {sendEachForMulticast: async (m) => {
    message = m;
    return {successCount: 1, responses: [
      {success: true},
      {success: false, error: {code: "messaging/registration-token-not-registered"}},
    ]};
  }};
  const sent = await sendDayRecordPushes(db, messaging, new Date("2026-10-01T05:00:00Z"));
  assert.equal(sent, 1);
  assert.deepEqual(message.tokens, ["good", "dead"]);
  assert.equal(message.apns.payload.aps["content-available"], 1);
  assert.equal(message.notification, undefined, "silent: no banner");
  assert.deepEqual(deleted, ["dead"]);
  // 05:00 UTC is 11 PM in Edmonton (MDT).
  assert.deepEqual(queried, [["nightlyPushUtcHour", "==", 5]]);
});
