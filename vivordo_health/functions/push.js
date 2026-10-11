"use strict";

/**
 * Sends one notification to every device a person has registered, unless
 * they've turned notifications off overall or the given setting off (on
 * unless false). Drops tokens the service says are gone.
 * @param {object} user User document reference.
 * @param {object} messaging Admin Messaging instance.
 * @param {string} setting The preferences key for this kind of push.
 * @param {object} message {notification, data}.
 */
async function pushToUser(user, messaging, setting, message) {
  const [profile, tokens] = await Promise.all([
    user.get(), user.collection("notification_tokens").get(),
  ]);
  const preferences = profile.data()?.preferences;
  if (preferences?.notificationsEnabled === false ||
      preferences?.[setting] === false) return;
  const valid = tokens.docs.filter((d) =>
    typeof d.get("token") === "string" && d.get("token"));
  if (!valid.length) return;
  const response = await messaging.sendEachForMulticast({
    tokens: valid.map((d) => d.get("token")),
    ...message,
    apns: {payload: {aps: {sound: "default"}}},
  });
  await Promise.all(response.responses.map((result, i) =>
    !result.success && ["messaging/registration-token-not-registered",
      "messaging/invalid-registration-token"].includes(result.error?.code) ?
      valid[i].ref.delete() : null));
}

module.exports = {pushToUser};
