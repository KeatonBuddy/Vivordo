"use strict";

// Nightly silent push that wakes the app to write its day records for
// Effort (docs/scores.md §5), so a day is recorded even when the app was
// last opened before the evening. Best effort: iOS may delay or drop a
// silent push, and never wakes an app the user swiped away.

const INVALID_TOKEN = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Sends the silent push to every device where it's 11 PM. Each device
 * stores the UTC hour of its local 11 PM (`nightlyPushUtcHour`) with its
 * token, refreshed whenever the app starts.
 * ponytail: a device not opened since a daylight-saving change is an hour
 * off (10 PM or midnight); both still record the day, since the app syncs
 * today and yesterday.
 * @param {object} db Admin Firestore instance.
 * @param {object} messaging Admin Messaging instance.
 * @param {Date} now Current time.
 * @return {Promise<number>} Pushes accepted by FCM.
 */
async function sendDayRecordPushes(db, messaging, now = new Date()) {
  const snapshot = await db.collectionGroup("notification_tokens")
      .where("nightlyPushUtcHour", "==", now.getUTCHours())
      .select("token")
      .get();
  const devices = snapshot.docs.filter((doc) =>
    typeof doc.get("token") === "string" && doc.get("token").length > 0);
  let sent = 0;
  for (let i = 0; i < devices.length; i += 500) {
    const chunk = devices.slice(i, i + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: chunk.map((doc) => doc.get("token")),
      data: {type: "day_record_sync"},
      apns: {
        headers: {"apns-push-type": "background", "apns-priority": "5"},
        payload: {aps: {"content-available": 1}},
      },
      android: {priority: "normal"},
    });
    await Promise.all(response.responses.map((result, index) =>
      !result.success && INVALID_TOKEN.has(result.error?.code) ?
        chunk[index].ref.delete() : null));
    sent += response.successCount;
  }
  return sent;
}

module.exports = {sendDayRecordPushes};
