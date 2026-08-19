const {setGlobalOptions} = require("firebase-functions");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const Anthropic = require("@anthropic-ai/sdk");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

// Circle challenge callables, progress triggers, and expiration scheduler.
// Loading this module after Firebase Admin initialization keeps all functions
// on the same shared Admin app and Firestore connection pool.
Object.assign(exports, require("./challenges"));

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
let anthropicClient;

/**
 * Resolves the Anthropic secret at runtime and reuses the client in warm
 * function containers.
 *
 * @return {Anthropic} The configured Anthropic client.
 */
function getAnthropicClient() {
  if (!anthropicClient) {
    anthropicClient = new Anthropic({apiKey: anthropicApiKey.value()});
  }
  return anthropicClient;
}

const googleHealthClientId = defineSecret("GOOGLE_HEALTH_CLIENT_ID");
const googleHealthClientSecret = defineSecret("GOOGLE_HEALTH_CLIENT_SECRET");
const whoopClientId = defineSecret("WHOOP_CLIENT_ID");
const whoopClientSecret = defineSecret("WHOOP_CLIENT_SECRET");

// Sends a private push notification to an activity owner when a Circle friend
// likes or comments. The engagement document is already created atomically
// with the like/comment, making it a reliable, de-duplicated trigger source.
exports.circleEngagementNotification = onDocumentCreated(
    "users/{ownerUid}/circle_engagement/{eventId}",
    async (event) => {
      const engagement = event.data?.data();
      const ownerUid = event.params.ownerUid;
      const type = engagement?.type;
      const actorUid = engagement?.actorUid;
      const activityId = engagement?.activityId;

      if (!engagement || !["like", "comment"].includes(type) ||
          !actorUid || !activityId || actorUid === ownerUid) {
        console.warn("Circle notification skipped: invalid engagement", {
          ownerUid,
          eventId: event.params.eventId,
          type,
          hasActorUid: Boolean(actorUid),
          hasActivityId: Boolean(activityId),
        });
        return;
      }

      const db = admin.firestore();
      const owner = db.collection("users").doc(ownerUid);
      const actorProfile = db.collection("users").doc(actorUid)
          .collection("circle").doc("profile");
      const activity = owner.collection("circle_activity").doc(activityId);
      const tokens = owner.collection("notification_tokens");
      const [ownerSnapshot, actorSnapshot, tokenSnapshot] =
        await Promise.all([
          owner.get(),
          actorProfile.get(),
          tokens.get(),
        ]);

      if (ownerSnapshot.data()?.preferences?.circleNotificationsEnabled ===
          false) {
        console.info("Circle notification disabled by activity owner", {
          ownerUid,
          type,
        });
        return;
      }
      if (tokenSnapshot.empty) {
        console.warn("Circle notification skipped: owner has no FCM tokens", {
          ownerUid,
          type,
        });
        return;
      }

      const actorName = actorSnapshot.data()?.username || "A Circle friend";
      const title = "Circle";
      let body;

      if (type === "like") {
        body = `${actorName} liked your post`;
      } else {
        const commentId = engagement.commentId;
        let commentText = "on your post";
        if (commentId) {
          const comment = await activity.collection("comments")
              .doc(commentId).get();
          const text = comment.data()?.text;
          if (typeof text === "string" && text.trim()) {
            commentText = text.trim().slice(0, 160);
          }
        }
        body = `${actorName} commented: ${commentText}`;
      }

      const tokenDocuments = tokenSnapshot.docs.filter((document) =>
        typeof document.data().token === "string" &&
        document.data().token.length > 0,
      );
      if (tokenDocuments.length === 0) {
        console.warn("Circle notification skipped: no valid token values", {
          ownerUid,
          tokenDocumentCount: tokenSnapshot.size,
        });
        return;
      }
      const invalidCodes = new Set([
        "messaging/registration-token-not-registered",
        "messaging/invalid-registration-token",
      ]);

      for (let start = 0; start < tokenDocuments.length; start += 500) {
        const chunk = tokenDocuments.slice(start, start + 500);
        const response = await admin.messaging().sendEachForMulticast({
          tokens: chunk.map((document) => document.data().token),
          notification: {title, body},
          data: {
            screen: "circle",
            type: `circle_${type}`,
            activityId,
          },
          apns: {
            headers: {"apns-priority": "10"},
            payload: {aps: {sound: "default"}},
          },
          android: {notification: {sound: "default"}},
        });

        const staleDeletes = [];
        const deliveryErrors = [];
        response.responses.forEach((result, index) => {
          if (!result.success && invalidCodes.has(result.error?.code)) {
            staleDeletes.push(chunk[index].ref.delete());
          }
          if (!result.success) {
            deliveryErrors.push({
              code: result.error?.code || "unknown",
              message: result.error?.message || "Unknown messaging error",
            });
          }
        });
        await Promise.all(staleDeletes);
        console.info("Circle notification delivery completed", {
          ownerUid,
          type,
          activityId,
          successCount: response.successCount,
          failureCount: response.failureCount,
          staleTokensRemoved: staleDeletes.length,
          errors: deliveryErrors,
        });
      }
    },
);

// Sends a push notification when a new incoming Circle friend request is
// created. A requester can only have one pending document per recipient, so
// using an on-create trigger also prevents duplicate notifications when the
// same request document is updated.
exports.friendRequestNotification = onDocumentCreated(
    "users/{recipientUid}/circle/relationships/friend_requests/{requesterUid}",
    async (event) => {
      const request = event.data?.data();
      const recipientUid = event.params.recipientUid;
      const requesterUid = event.params.requesterUid;

      if (!request || request.fromUid !== requesterUid ||
          request.toUid !== recipientUid || requesterUid === recipientUid) {
        console.warn("Friend request notification skipped: invalid request", {
          recipientUid,
          requesterUid,
          fromUid: request?.fromUid,
          toUid: request?.toUid,
        });
        return;
      }

      const db = admin.firestore();
      const recipient = db.collection("users").doc(recipientUid);
      const requester = db.collection("users").doc(requesterUid);
      const requesterProfile = requester.collection("circle").doc("profile");
      const tokens = recipient.collection("notification_tokens");
      const [recipientSnapshot, requesterSnapshot, profileSnapshot,
        tokenSnapshot] = await Promise.all([
        recipient.get(),
        requester.get(),
        requesterProfile.get(),
        tokens.get(),
      ]);

      if (recipientSnapshot.data()?.preferences
          ?.circleNotificationsEnabled === false) {
        console.info("Friend request notification disabled by recipient", {
          recipientUid,
          requesterUid,
        });
        return;
      }

      const tokenDocuments = tokenSnapshot.docs.filter((document) =>
        typeof document.data().token === "string" &&
        document.data().token.length > 0,
      );
      if (tokenDocuments.length === 0) {
        console.warn(
            "Friend request notification skipped: recipient has no FCM tokens",
            {recipientUid, requesterUid},
        );
        return;
      }

      const profile = profileSnapshot.data();
      const requesterData = requesterSnapshot.data();
      const requesterName = profile?.username ||
        requesterData?.displayName || requesterData?.username ||
        "A Vivordo user";
      const title = "New Friend Request";
      const body = `from ${requesterName}`;
      const invalidCodes = new Set([
        "messaging/registration-token-not-registered",
        "messaging/invalid-registration-token",
      ]);

      for (let start = 0; start < tokenDocuments.length; start += 500) {
        const chunk = tokenDocuments.slice(start, start + 500);
        const response = await admin.messaging().sendEachForMulticast({
          tokens: chunk.map((document) => document.data().token),
          notification: {title, body},
          data: {
            screen: "circle",
            tab: "friends",
            type: "circle_friend_request",
            requesterUid,
          },
          apns: {
            headers: {"apns-priority": "10"},
            payload: {aps: {sound: "default"}},
          },
          android: {notification: {sound: "default"}},
        });

        const staleDeletes = [];
        const deliveryErrors = [];
        response.responses.forEach((result, index) => {
          if (!result.success && invalidCodes.has(result.error?.code)) {
            staleDeletes.push(chunk[index].ref.delete());
          }
          if (!result.success) {
            deliveryErrors.push({
              code: result.error?.code || "unknown",
              message: result.error?.message || "Unknown messaging error",
            });
          }
        });
        await Promise.all(staleDeletes);
        console.info("Friend request notification delivery completed", {
          recipientUid,
          requesterUid,
          successCount: response.successCount,
          failureCount: response.failureCount,
          staleTokensRemoved: staleDeletes.length,
          errors: deliveryErrors,
        });
      }
    },
);

// Sends a personal push notification only when an achievement is newly
// unlocked. Progress-only writes are ignored; tiered achievements notify
// again when the user advances from bronze to silver or silver to gold.
exports.achievementUnlockNotification = onDocumentWritten(
    "users/{userUid}/achievements/{achievementId}",
    async (event) => {
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      const userUid = event.params.userUid;
      const achievementId = event.params.achievementId;

      if (!after) return;

      const tierRank = (tier) => ({bronze: 1, silver: 2, gold: 3})[tier] || 0;
      const completedNow = after.completed === true &&
        before?.completed !== true;
      const tierAdvanced = tierRank(after.tier) > tierRank(before?.tier);
      const beforeTiers = new Set(Array.isArray(before?.earnedTiers) ?
        before.earnedTiers : []);
      const newlyEarnedTier = Array.isArray(after.earnedTiers) &&
        after.earnedTiers.some((tier) => !beforeTiers.has(tier));

      if (!completedNow && !tierAdvanced && !newlyEarnedTier) {
        return;
      }

      const db = admin.firestore();
      const user = db.collection("users").doc(userUid);
      const [userSnapshot, tokenSnapshot] = await Promise.all([
        user.get(),
        user.collection("notification_tokens").get(),
      ]);

      if (userSnapshot.data()?.preferences?.notificationsEnabled === false) {
        console.info("Achievement notification disabled by user", {
          userUid,
          achievementId,
        });
        return;
      }

      const tokenDocuments = tokenSnapshot.docs.filter((document) =>
        typeof document.data().token === "string" &&
        document.data().token.length > 0,
      );
      if (tokenDocuments.length === 0) {
        console.warn("Achievement notification skipped: user has no tokens", {
          userUid,
          achievementId,
        });
        return;
      }

      const achievementName = typeof after.name === "string" &&
        after.name.trim() ? after.name.trim() : achievementId;
      const invalidCodes = new Set([
        "messaging/registration-token-not-registered",
        "messaging/invalid-registration-token",
      ]);

      for (let start = 0; start < tokenDocuments.length; start += 500) {
        const chunk = tokenDocuments.slice(start, start + 500);
        const data = {
          screen: "circle",
          tab: "goals",
          type: "achievement_unlocked",
          achievementId,
        };
        if (typeof after.tier === "string" && after.tier) {
          data.achievementTier = after.tier;
        }
        const response = await admin.messaging().sendEachForMulticast({
          tokens: chunk.map((document) => document.data().token),
          notification: {
            title: "New Achievement",
            body: achievementName,
          },
          data,
          apns: {
            headers: {"apns-priority": "10"},
            payload: {aps: {sound: "default"}},
          },
          android: {notification: {sound: "default"}},
        });

        const staleDeletes = [];
        const deliveryErrors = [];
        response.responses.forEach((result, index) => {
          if (!result.success && invalidCodes.has(result.error?.code)) {
            staleDeletes.push(chunk[index].ref.delete());
          }
          if (!result.success) {
            deliveryErrors.push({
              code: result.error?.code || "unknown",
              message: result.error?.message || "Unknown messaging error",
            });
          }
        });
        await Promise.all(staleDeletes);
        console.info("Achievement notification delivery completed", {
          userUid,
          achievementId,
          achievementName,
          tier: after.tier || null,
          successCount: response.successCount,
          failureCount: response.failureCount,
          staleTokensRemoved: staleDeletes.length,
          errors: deliveryErrors,
        });
      }
    },
);

// =============================================================================
// pandaClaude — real-time HTTPS Callable proxy for Anthropic API
// Security: API key stays server-side (VIV-309).
// =============================================================================

exports.pandaClaude = onCall({secrets: [anthropicApiKey]}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }

  const {system, user, maxTokens} = request.data;
  if (!system || !user) {
    throw new HttpsError("invalid-argument", "system and user are required.");
  }

  // maxTokens: 300 for chat turns, 1800 for spike analysis (set by client).
  // Fall back to 300 (chat default) if omitted.
  const outputCap =
      (typeof maxTokens === "number" && maxTokens > 0) ? maxTokens : 300;

  const systemBlocks = Array.isArray(system) ?
    system :
    [
      {
        type: "text",
        text: String(system),
        cache_control: {type: "ephemeral"},
      },
    ];
  const userBlocks = Array.isArray(user) ?
    user :
    [{type: "text", text: String(user)}];

  const msg = await getAnthropicClient().messages.create({
    model: "claude-sonnet-4-5",
    max_tokens: outputCap,
    system: systemBlocks,
    messages: [{role: "user", content: userBlocks}],
  });

  const text = (msg.content || []).reduce((acc, block) => {
    if (block && block.type === "text") {
      return acc ? `${acc}\n${block.text}` : block.text;
    }
    return acc;
  }, "");

  // VIV-307: log cache token usage so billing dashboard shows cache hits.
  console.log("[pandaClaude] usage", JSON.stringify({
    input: msg.usage?.input_tokens ?? 0,
    output: msg.usage?.output_tokens ?? 0,
    cache_create: msg.usage?.cache_creation_input_tokens ?? 0,
    cache_read: msg.usage?.cache_read_input_tokens ?? 0,
  }));

  return {
    text,
    usage: msg.usage || {},
  };
});

// =============================================================================
// Fitbit metric sync through the Google Health API
//
// Tokens are stored in a top-level collection that has no client Firestore
// rule, so only Admin SDK code can read them. The user document contains only
// connection status and timestamps.
// =============================================================================

const _GOOGLE_HEALTH_SECRETS = [
  googleHealthClientId,
  googleHealthClientSecret,
];
const _GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const _GOOGLE_HEALTH_API = "https://health.googleapis.com/v4";
const _GOOGLE_SCOPES = [
  "https://www.googleapis.com/auth/" +
      "googlehealth.activity_and_fitness.readonly",
  "https://www.googleapis.com/auth/" +
      "googlehealth.health_metrics_and_measurements.readonly",
  "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
];
const _IOS_CALLBACK = "vivordo-fitbit://oauth2redirect";

/* eslint-disable require-jsdoc */
function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be logged in.");
  }
  return request.auth.uid;
}

function googleHealthCallbackUrl() {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!project) {
    throw new HttpsError("internal", "Firebase project ID is unavailable.");
  }
  return `https://us-central1-${project}.cloudfunctions.net/` +
      "googleHealthOAuthCallback";
}

function whoopCallbackUrl() {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (!project) {
    throw new HttpsError("internal", "Firebase project ID is unavailable.");
  }
  return `https://us-central1-${project}.cloudfunctions.net/` +
      "whoopOAuthCallback";
}

async function requestGoogleToken(parameters) {
  const response = await fetch(_GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      ...parameters,
      client_id: googleHealthClientId.value(),
      client_secret: googleHealthClientSecret.value(),
    }),
  });
  const body = await response.json();
  if (!response.ok) {
    console.error(
        "[Google Health] token request failed",
        response.status,
        body,
    );
    throw new HttpsError(
        "failed-precondition",
        "Google Health could not complete authorization.",
    );
  }
  return body;
}

async function saveGoogleHealthTokens(uid, tokens) {
  const expiresIn = Number(tokens.expires_in || 3600);
  const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + expiresIn * 1000,
  );
  const values = {
    accessToken: tokens.access_token,
    scope: tokens.scope || "",
    tokenType: tokens.token_type || "Bearer",
    expiresAt,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (tokens.refresh_token) values.refreshToken = tokens.refresh_token;
  await admin.firestore()
      .collection("google_health_credentials")
      .doc(uid)
      .set(values, {merge: true});
}

async function getGoogleHealthAccessToken(uid) {
  const reference =
      admin.firestore().collection("google_health_credentials").doc(uid);
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    throw new HttpsError(
        "failed-precondition",
        "Connect Fitbit through Google Health before syncing.",
    );
  }

  const credentials = snapshot.data();
  const expiresAt = credentials.expiresAt?.toMillis?.() || 0;
  if (expiresAt > Date.now() + 5 * 60 * 1000) {
    return credentials.accessToken;
  }

  if (!credentials.refreshToken) {
    throw new HttpsError(
        "failed-precondition",
        "Reconnect Fitbit to grant offline access.",
    );
  }
  const tokens = await requestGoogleToken({
    grant_type: "refresh_token",
    refresh_token: credentials.refreshToken,
  });
  await saveGoogleHealthTokens(uid, tokens);
  return tokens.access_token;
}

async function googleHealthDailyRollup(accessToken, dataType, start, end) {
  const response = await fetch(
      `${_GOOGLE_HEALTH_API}/users/me/dataTypes/${dataType}/` +
      "dataPoints:dailyRollUp",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          range: {
            start: civilDate(start),
            end: civilDate(end),
          },
          windowSizeDays: 1,
          pageSize: 90,
          dataSourceFamily:
              "users/me/dataSourceFamilies/google-wearables",
        }),
      },
  );
  if (response.status === 403 || response.status === 404) {
    console.warn(`[Google Health] optional data unavailable: ${dataType}`);
    return [];
  }
  if (!response.ok) {
    const body = await response.text();
    console.error(
        "[Google Health] API request failed",
        response.status,
        dataType,
        body,
    );
    throwGoogleHealthError(response.status, body);
  }
  const body = await response.json();
  return body.rollupDataPoints || [];
}

function throwGoogleHealthError(status, body) {
  let googleError;
  try {
    googleError = JSON.parse(body)?.error;
  } catch (_) {
    // Preserve the generic error below when Google returns a non-JSON body.
  }
  const accountDetail = googleError?.details?.find(
      (detail) => detail?.reason === "ACCOUNT_NOT_LINKED",
  );
  if (accountDetail) {
    throw new HttpsError(
        "failed-precondition",
        "Finish setting up Google Health before syncing Fitbit.",
        {
          reason: "ACCOUNT_NOT_LINKED",
          setupUrl:
              accountDetail.metadata?.redirect_uri ||
              "https://fitbit.google.com/auth/signup",
        },
    );
  }
  throw new HttpsError(
      status === 401 ? "unauthenticated" : "unavailable",
      "Fitbit data could not be synced from Google Health.",
  );
}

async function googleHealthSleep(accessToken, start, end) {
  const dataPoints = [];
  let pageToken;
  const filter =
      `sleep.interval.civil_end_time >= "${dateKey(start)}" AND ` +
      `sleep.interval.civil_end_time < "${dateKey(end)}"`;
  do {
    const query = new URLSearchParams({
      filter,
      pageSize: "25",
    });
    if (pageToken) query.set("pageToken", pageToken);
    const response = await fetch(
        `${_GOOGLE_HEALTH_API}/users/me/dataTypes/sleep/dataPoints?${query}`,
        {
          headers: {
            "Authorization": `Bearer ${accessToken}`,
            "Accept": "application/json",
          },
        },
    );
    if (response.status === 403 || response.status === 404) {
      console.warn("[Google Health] optional data unavailable: sleep");
      return [];
    }
    if (!response.ok) {
      const body = await response.text();
      console.error(
          "[Google Health] sleep request failed",
          response.status,
          body,
      );
      throwGoogleHealthError(response.status, body);
    }
    const body = await response.json();
    dataPoints.push(...(body.dataPoints || []));
    pageToken = body.nextPageToken;
  } while (pageToken);
  return dataPoints.filter((point) => {
    const platform = point.dataSource?.platform;
    return platform === "FITBIT" || platform === "FITBIT_WEB_API";
  });
}

function civilDate(date) {
  return {
    date: {
      year: date.getUTCFullYear(),
      month: date.getUTCMonth() + 1,
      day: date.getUTCDate(),
    },
    time: {hours: 0, minutes: 0, seconds: 0, nanos: 0},
  };
}

function civilDateKey(value) {
  const date = value?.date || value;
  if (!date?.year || !date?.month || !date?.day) return null;
  return [
    String(date.year).padStart(4, "0"),
    String(date.month).padStart(2, "0"),
    String(date.day).padStart(2, "0"),
  ].join("-");
}

function dateKey(date) {
  return date.toISOString().slice(0, 10);
}

function metricPayload(values) {
  const payload = {};
  for (const [key, value] of Object.entries(values)) {
    if (value !== undefined && value !== null && Number.isFinite(value)) {
      payload[key] = value;
    }
  }
  return payload;
}

function addMetric(days, day, key, values) {
  if (!day || Object.keys(values).length === 0) return;
  if (!days[day]) days[day] = {};
  days[day][key] = {
    ...values,
    source: "fitbit",
    syncedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function fetchGoogleHealthData(accessToken, start, end) {
  const types = [
    "steps",
    "distance",
    "floors",
    "active-energy-burned",
    "heart-rate",
    "weight",
  ];
  const results = await Promise.all(types.map(async (type) => {
    if (type !== "heart-rate") {
      return googleHealthDailyRollup(accessToken, type, start, end);
    }
    const entries = [];
    const chunkStart = new Date(start);
    while (chunkStart < end) {
      const chunkEnd = new Date(chunkStart);
      chunkEnd.setUTCDate(chunkEnd.getUTCDate() + 14);
      if (chunkEnd > end) chunkEnd.setTime(end.getTime());
      entries.push(...await googleHealthDailyRollup(
          accessToken,
          type,
          chunkStart,
          chunkEnd,
      ));
      chunkStart.setTime(chunkEnd.getTime());
    }
    return entries;
  }));
  const data = Object.fromEntries(types.map((type, index) => [
    type,
    results[index],
  ]));
  data.sleep = await googleHealthSleep(accessToken, start, end);
  return data;
}

function sleepMinutes(sleep) {
  const summaryMinutes = Number(sleep.summary?.minutesAsleep);
  if (Number.isFinite(summaryMinutes)) return summaryMinutes;
  return (sleep.stages || []).reduce((total, stage) => {
    if (!["LIGHT", "DEEP", "REM", "ASLEEP"].includes(stage.type)) {
      return total;
    }
    const start = Date.parse(stage.startTime);
    const end = Date.parse(stage.endTime);
    return Number.isFinite(start) && Number.isFinite(end) && end > start ?
      total + (end - start) / 60000 :
      total;
  }, 0);
}

function normalizeGoogleHealthData(data) {
  const days = {};
  for (const [type, entries] of Object.entries(data)) {
    if (type === "sleep") continue;
    for (const entry of entries) {
      const day = civilDateKey(entry.civilStartTime);
      addMetric(days, day, "steps", metricPayload({
        sum: Number(entry.steps?.countSum),
        avg: Number(entry.steps?.countSum),
        unit: "steps",
        dimension: "activity",
      }));
      addMetric(days, day, "distance", metricPayload({
        sum: Number(entry.distance?.millimetersSum) / 1000000,
        avg: Number(entry.distance?.millimetersSum) / 1000000,
        unit: "km",
        dimension: "activity",
      }));
      addMetric(days, day, "flights_climbed", metricPayload({
        sum: Number(entry.floors?.countSum),
        avg: Number(entry.floors?.countSum),
        unit: "flights",
        dimension: "activity",
      }));
      addMetric(days, day, "active_calories", metricPayload({
        sum: Number(entry.activeEnergyBurned?.kcalSum),
        avg: Number(entry.activeEnergyBurned?.kcalSum),
        unit: "kcal",
        dimension: "activity",
      }));
      addMetric(days, day, "heart_rate", metricPayload({
        avg: Number(entry.heartRate?.beatsPerMinuteAvg),
        min: Number(entry.heartRate?.beatsPerMinuteMin),
        max: Number(entry.heartRate?.beatsPerMinuteMax),
        unit: "bpm",
        dimension: "cardiovascular",
      }));
      addMetric(days, day, "weight", metricPayload({
        avg: Number(entry.weight?.weightGramsAvg) / 1000,
        unit: "kg",
        dimension: "body",
      }));
    }
  }
  const sleepByDay = {};
  for (const point of data.sleep || []) {
    const sleep = point.sleep;
    const day = civilDateKey(sleep?.interval?.civilEndTime);
    const minutes = sleepMinutes(sleep || {});
    if (day && minutes > 0) {
      sleepByDay[day] = (sleepByDay[day] || 0) + minutes;
    }
  }
  for (const [day, minutes] of Object.entries(sleepByDay)) {
    const hours = minutes / 60;
    addMetric(days, day, "sleep", metricPayload({
      avg: hours,
      min: hours,
      max: hours,
      unit: "hours",
      dimension: "sleep",
    }));
  }
  return days;
}

function addFitbitWellness(days) {
  for (const metrics of Object.values(days)) {
    let weightedScore = 0;
    let totalWeight = 0;
    const sleep = metrics.sleep?.avg;
    const steps = metrics.steps?.sum;
    const heartRate = metrics.heart_rate_scan?.avg;
    if (Number.isFinite(sleep)) {
      weightedScore += Math.max(0, Math.min(100, sleep / 8 * 100)) * 0.30;
      totalWeight += 30;
    }
    if (Number.isFinite(steps)) {
      weightedScore += Math.max(0, Math.min(100, steps / 10000 * 100)) * 0.20;
      totalWeight += 20;
    }
    if (Number.isFinite(heartRate)) {
      const distanceFromOptimal = heartRate < 60 ?
        60 - heartRate : heartRate > 80 ? heartRate - 80 : 0;
      const heartRateScore = Math.max(
          0,
          Math.min(100, 100 - distanceFromOptimal * 2.5),
      );
      weightedScore += heartRateScore * 0.15;
      totalWeight += 15;
    }
    if (totalWeight > 0) {
      metrics.wellness = {
        avg: weightedScore / totalWeight * 100,
        unit: "score",
        source: "computed",
        computedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }
  }
}

// =============================================================================
// WHOOP OAuth
//
// The callable returns only the consent URL. The client secret, authorization
// code, and eventual tokens remain in Firebase Functions.
// =============================================================================

const _WHOOP_AUTHORIZATION_URL =
    "https://api.prod.whoop.com/oauth/oauth2/auth";
const _WHOOP_TOKEN_URL = "https://api.prod.whoop.com/oauth/oauth2/token";
const _WHOOP_IOS_CALLBACK = "vivordo-whoop://oauth2redirect";
const _WHOOP_SECRETS = [whoopClientId, whoopClientSecret];
const _WHOOP_SCOPES = [
  "offline",
  "read:recovery",
  "read:cycles",
  "read:sleep",
  "read:workout",
  "read:body_measurement",
];

async function requestWhoopToken(parameters) {
  const response = await fetch(_WHOOP_TOKEN_URL, {
    method: "POST",
    signal: AbortSignal.timeout(15000),
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json",
    },
    body: new URLSearchParams({
      ...parameters,
      client_id: whoopClientId.value(),
      client_secret: whoopClientSecret.value(),
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    console.error("[WHOOP] token request failed", response.status, {
      error: body.error,
      errorDescription: body.error_description,
    });
    if (response.status === 400 || response.status === 401) {
      throw new HttpsError(
          "unauthenticated",
          "WHOOP authorization has expired. Reconnect WHOOP.",
      );
    }
    if (response.status === 429) {
      throw new HttpsError(
          "resource-exhausted",
          "WHOOP request limit reached. Please try again later.",
      );
    }
    throw new HttpsError(
        "unavailable",
        "WHOOP authorization could not be completed.",
    );
  }
  return body;
}

async function saveWhoopTokens(uid, tokens) {
  const expiresIn = Number(tokens.expires_in || 3600);
  const expiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + expiresIn * 1000,
  );
  const values = {
    accessToken: tokens.access_token,
    scope: tokens.scope || "",
    tokenType: tokens.token_type || "Bearer",
    expiresAt,
    refreshLease: admin.firestore.FieldValue.delete(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (tokens.refresh_token) values.refreshToken = tokens.refresh_token;
  await admin.firestore()
      .collection("whoop_credentials")
      .doc(uid)
      .set(values, {merge: true});
}

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function getWhoopAccessToken(uid, invalidAccessToken) {
  const reference =
      admin.firestore().collection("whoop_credentials").doc(uid);
  for (let attempt = 0; attempt < 20; attempt++) {
    const now = Date.now();
    const leaseId = crypto.randomBytes(16).toString("hex");
    let result;
    await admin.firestore().runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        result = {missing: true};
        return;
      }
      const credentials = snapshot.data();
      const expiresAt = credentials.expiresAt?.toMillis?.() || 0;
      const tokenWasReplaced = invalidAccessToken &&
          credentials.accessToken !== invalidAccessToken;
      const canReuse = tokenWasReplaced ? expiresAt > now :
          !invalidAccessToken && expiresAt > now + 5 * 60 * 1000;
      if (canReuse && credentials.accessToken) {
        result = {accessToken: credentials.accessToken};
        return;
      }

      const leaseExpiresAt =
          credentials.refreshLease?.expiresAt?.toMillis?.() || 0;
      if (leaseExpiresAt > now) {
        result = {waiting: true};
        return;
      }
      if (!credentials.refreshToken) {
        result = {missingRefreshToken: true};
        return;
      }
      transaction.set(reference, {
        refreshLease: {
          id: leaseId,
          expiresAt: admin.firestore.Timestamp.fromMillis(now + 60 * 1000),
        },
      }, {merge: true});
      result = {
        refreshToken: credentials.refreshToken,
        leaseId,
      };
    });

    if (result.missing) {
      throw new HttpsError(
          "failed-precondition",
          "Connect WHOOP before syncing.",
      );
    }
    if (result.missingRefreshToken) {
      throw new HttpsError(
          "failed-precondition",
          "Reconnect WHOOP to grant offline access.",
      );
    }
    if (result.accessToken) return result.accessToken;
    if (result.refreshToken) {
      try {
        const tokens = await requestWhoopToken({
          grant_type: "refresh_token",
          refresh_token: result.refreshToken,
          scope: "offline",
        });
        await saveWhoopTokens(uid, tokens);
        return tokens.access_token;
      } catch (error) {
        await admin.firestore().runTransaction(async (transaction) => {
          const snapshot = await transaction.get(reference);
          if (snapshot.data()?.refreshLease?.id === result.leaseId) {
            transaction.set(reference, {
              refreshLease: admin.firestore.FieldValue.delete(),
            }, {merge: true});
          }
        });
        throw error;
      }
    }
    await wait(500);
  }
  throw new HttpsError(
      "unavailable",
      "WHOOP authorization is being refreshed. Please try again.",
  );
}

const _WHOOP_API = "https://api.prod.whoop.com/developer";

async function whoopApiRequest(uid, path, query, optional = false) {
  let accessToken = await getWhoopAccessToken(uid);
  for (let attempt = 0; attempt < 2; attempt++) {
    const url = new URL(`${_WHOOP_API}${path}`);
    if (query) url.search = new URLSearchParams(query).toString();
    const response = await fetch(url, {
      signal: AbortSignal.timeout(15000),
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Accept": "application/json",
      },
    });
    if (response.status === 401 && attempt === 0) {
      accessToken = await getWhoopAccessToken(uid, accessToken);
      continue;
    }
    if (optional && response.status === 404) return null;
    if (response.status === 429) {
      throw new HttpsError(
          "resource-exhausted",
          "WHOOP request limit reached. Please sync again later.",
      );
    }
    if (!response.ok) {
      console.error("[WHOOP] API request failed", response.status, path);
      throw new HttpsError(
          response.status === 401 ? "unauthenticated" : "unavailable",
          "WHOOP data could not be synced.",
      );
    }
    return response.json();
  }
  throw new HttpsError("unauthenticated", "Reconnect WHOOP before syncing.");
}

async function revokeWhoopAccess(uid) {
  let accessToken = await getWhoopAccessToken(uid);
  for (let attempt = 0; attempt < 2; attempt++) {
    let response;
    try {
      response = await fetch(`${_WHOOP_API}/v2/user/access`, {
        method: "DELETE",
        signal: AbortSignal.timeout(15000),
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Accept": "application/json",
        },
      });
    } catch (error) {
      console.warn("[WHOOP] revoke request failed", error);
      throw new HttpsError(
          "unavailable",
          "WHOOP could not be disconnected. Please try again.",
      );
    }
    if (response.status === 204 || response.status === 404) return;
    if (response.status === 401) {
      if (attempt === 0) {
        accessToken = await getWhoopAccessToken(uid, accessToken);
        continue;
      }
      // WHOOP no longer accepts either a refreshed or existing credential.
      // Treat the remote authorization as already inaccessible.
      return;
    }
    if (response.status === 429) {
      throw new HttpsError(
          "resource-exhausted",
          "WHOOP request limit reached. Please disconnect again later.",
      );
    }
    console.error("[WHOOP] revoke request failed", response.status);
    throw new HttpsError(
        "unavailable",
        "WHOOP could not be disconnected. Please try again.",
    );
  }
}

async function whoopCollection(uid, path, start, end) {
  const records = [];
  const seenTokens = new Set();
  let nextToken;
  do {
    const query = {
      limit: "25",
      start: start.toISOString(),
      end: end.toISOString(),
    };
    if (nextToken) query.nextToken = nextToken;
    const body = await whoopApiRequest(uid, path, query);
    records.push(...(Array.isArray(body.records) ? body.records : []));
    nextToken = body.next_token;
    if (nextToken && seenTokens.has(nextToken)) {
      throw new HttpsError("unavailable", "WHOOP pagination did not advance.");
    }
    if (nextToken) seenTokens.add(nextToken);
  } while (nextToken);
  return records;
}

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

function whoopNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function setWhoopMetric(days, day, key, values) {
  if (!day) return;
  const payload = {};
  for (const [name, value] of Object.entries(values)) {
    if (value === undefined || value === null) continue;
    if (typeof value === "number" && !Number.isFinite(value)) continue;
    payload[name] = value;
  }
  const hasMeasurement = ["avg", "min", "max", "sum", "count"]
      .some((name) => Number.isFinite(payload[name]));
  if (!hasMeasurement) return;
  if (!days[day]) days[day] = {};
  days[day][key] = {
    ...payload,
    source: "whoop",
    syncedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

function normalizeWhoopData({cycles, recoveries, sleeps, workouts, body}) {
  const days = {};
  const cyclesById = new Map(cycles.map((cycle) => [cycle.id, cycle]));
  const sleepsById = new Map(sleeps.map((sleep) => [sleep.id, sleep]));

  for (const cycle of cycles) {
    if (cycle.score_state !== "SCORED" || !cycle.score) continue;
    const day = whoopDateKey(cycle.start, cycle.timezone_offset);
    setWhoopMetric(days, day, "strain", {
      avg: whoopNumber(cycle.score.strain),
      unit: "score",
      dimension: "activity",
    });
    setWhoopMetric(days, day, "heart_rate", {
      avg: whoopNumber(cycle.score.average_heart_rate),
      max: whoopNumber(cycle.score.max_heart_rate),
      unit: "bpm",
      dimension: "cardiovascular",
    });
  }

  const sleepTotals = {};
  for (const sleep of sleeps) {
    if (sleep.score_state !== "SCORED" || !sleep.score) continue;
    const day = whoopDateKey(sleep.end, sleep.timezone_offset);
    if (!day) continue;
    const stages = sleep.score.stage_summary || {};
    const stageMinutes = {
      awake: (whoopNumber(stages.total_awake_time_milli) || 0) / 60000,
      core: (whoopNumber(stages.total_light_sleep_time_milli) || 0) / 60000,
      deep: (whoopNumber(stages.total_slow_wave_sleep_time_milli) || 0) /
          60000,
      rem: (whoopNumber(stages.total_rem_sleep_time_milli) || 0) / 60000,
    };
    const asleepMinutes = stageMinutes.core + stageMinutes.deep +
        stageMinutes.rem;
    if (!sleepTotals[day]) {
      sleepTotals[day] = {
        minutes: 0,
        stages: {awake: 0, core: 0, deep: 0, rem: 0},
        bedtime: null,
        wakeTime: null,
        mainSleep: null,
      };
    }
    const total = sleepTotals[day];
    total.minutes += asleepMinutes;
    for (const stage of Object.keys(total.stages)) {
      total.stages[stage] += stageMinutes[stage];
    }
    const start = Date.parse(sleep.start);
    const end = Date.parse(sleep.end);
    if (Number.isFinite(start) &&
        (!total.bedtime || start < total.bedtime.getTime())) {
      total.bedtime = new Date(start);
    }
    if (Number.isFinite(end) &&
        (!total.wakeTime || end > total.wakeTime.getTime())) {
      total.wakeTime = new Date(end);
    }
    if (!sleep.nap) total.mainSleep = sleep;
  }
  for (const [day, total] of Object.entries(sleepTotals)) {
    const score = total.mainSleep?.score || {};
    setWhoopMetric(days, day, "sleep", {
      avg: total.minutes / 60,
      min: total.minutes / 60,
      max: total.minutes / 60,
      unit: "hours",
      dimension: "sleep",
      bedtime: total.bedtime ?
        admin.firestore.Timestamp.fromDate(total.bedtime) : null,
      wakeTime: total.wakeTime ?
        admin.firestore.Timestamp.fromDate(total.wakeTime) : null,
      stages: total.stages,
      performance: whoopNumber(score.sleep_performance_percentage),
      consistency: whoopNumber(score.sleep_consistency_percentage),
      efficiency: whoopNumber(score.sleep_efficiency_percentage),
    });
    setWhoopMetric(days, day, "respiratory_rate", {
      avg: whoopNumber(score.respiratory_rate),
      unit: "breaths/min",
      dimension: "respiratory",
    });
  }

  for (const recovery of recoveries) {
    if (recovery.score_state !== "SCORED" || !recovery.score) continue;
    const sleep = sleepsById.get(recovery.sleep_id);
    const cycle = cyclesById.get(recovery.cycle_id);
    const timestamp = sleep?.end || cycle?.start || recovery.updated_at;
    const offset = sleep?.timezone_offset || cycle?.timezone_offset;
    const day = whoopDateKey(timestamp, offset);
    const score = recovery.score;
    setWhoopMetric(days, day, "recovery", {
      avg: whoopNumber(score.recovery_score),
      unit: "score",
      dimension: "recovery",
      calibrating: score.user_calibrating === true,
    });
    setWhoopMetric(days, day, "resting_heart_rate", {
      avg: whoopNumber(score.resting_heart_rate),
      unit: "bpm",
      dimension: "cardiovascular",
    });
    setWhoopMetric(days, day, "hrv", {
      avg: whoopNumber(score.hrv_rmssd_milli),
      unit: "ms",
      dimension: "cardiovascular",
    });
    setWhoopMetric(days, day, "blood_oxygen", {
      avg: whoopNumber(score.spo2_percentage),
      unit: "%",
      dimension: "respiratory",
    });
    setWhoopMetric(days, day, "skin_temperature", {
      avg: whoopNumber(score.skin_temp_celsius),
      unit: "°C",
      dimension: "body",
    });
  }

  const workoutsByDay = {};
  for (const workout of workouts) {
    if (workout.score_state !== "SCORED" || !workout.score) continue;
    const day = whoopDateKey(workout.start, workout.timezone_offset);
    if (!day) continue;
    if (!workoutsByDay[day]) {
      workoutsByDay[day] = {
        count: 0,
        minutes: 0,
        calories: 0,
        distance: 0,
        strain: 0,
      };
    }
    const summary = workoutsByDay[day];
    summary.count++;
    const start = Date.parse(workout.start);
    const end = Date.parse(workout.end);
    if (Number.isFinite(start) && Number.isFinite(end) && end > start) {
      summary.minutes += (end - start) / 60000;
    }
    summary.calories += (whoopNumber(workout.score.kilojoule) || 0) / 4.184;
    summary.distance += (whoopNumber(workout.score.distance_meter) || 0) /
        1000;
    summary.strain += whoopNumber(workout.score.strain) || 0;
  }
  for (const [day, summary] of Object.entries(workoutsByDay)) {
    setWhoopMetric(days, day, "exercise_time", {
      sum: summary.minutes,
      avg: summary.minutes,
      count: summary.count,
      unit: "min",
      dimension: "activity",
    });
    setWhoopMetric(days, day, "active_calories", {
      sum: summary.calories,
      avg: summary.calories,
      unit: "kcal",
      dimension: "activity",
    });
    setWhoopMetric(days, day, "distance", {
      sum: summary.distance,
      avg: summary.distance,
      unit: "km",
      dimension: "activity",
    });
    setWhoopMetric(days, day, "workout_strain", {
      sum: summary.strain,
      avg: summary.strain / summary.count,
      count: summary.count,
      unit: "score",
      dimension: "activity",
    });
  }

  if (body) {
    const latestCycle = cycles[0];
    const day = whoopDateKey(
        new Date().toISOString(),
        latestCycle?.timezone_offset,
    );
    setWhoopMetric(days, day, "weight", {
      avg: whoopNumber(body.weight_kilogram),
      unit: "kg",
      dimension: "body",
    });
  }
  return days;
}

exports.beginWhoopConnection = onCall(
    {secrets: [whoopClientId]},
    async (request) => {
      const uid = requireAuth(request);
      // WHOOP requires client-generated OAuth state values to be 8 characters.
      const state = crypto.randomBytes(6).toString("base64url");
      await admin.firestore()
          .collection("whoop_oauth_states")
          .doc(state)
          .set({
            uid,
            expiresAt: admin.firestore.Timestamp.fromMillis(
                Date.now() + 10 * 60 * 1000,
            ),
          });

      const authorizationUrl = new URL(_WHOOP_AUTHORIZATION_URL);
      authorizationUrl.search = new URLSearchParams({
        response_type: "code",
        client_id: whoopClientId.value(),
        redirect_uri: whoopCallbackUrl(),
        scope: _WHOOP_SCOPES.join(" "),
        state,
      }).toString();
      return {authorizationUrl: authorizationUrl.toString()};
    },
);

exports.whoopOAuthCallback = onRequest(
    {secrets: _WHOOP_SECRETS},
    async (request, response) => {
      const state = request.query.state;
      const code = request.query.code;
      const oauthError = request.query.error;
      const fail = (message) => response.redirect(
          `${_WHOOP_IOS_CALLBACK}?error=authorization_failed&` +
          `error_description=${encodeURIComponent(message)}`,
      );
      if (typeof state !== "string") return fail("Missing OAuth state.");

      const reference = admin.firestore()
          .collection("whoop_oauth_states")
          .doc(state);
      let values;
      await admin.firestore().runTransaction(async (transaction) => {
        const snapshot = await transaction.get(reference);
        if (snapshot.exists) {
          values = snapshot.data();
          transaction.delete(reference);
        }
      });
      if (!values || (values.expiresAt?.toMillis?.() || 0) < Date.now()) {
        return fail("The authorization request expired.");
      }
      if (oauthError || typeof code !== "string") {
        return fail("WHOOP authorization was cancelled.");
      }

      try {
        const tokens = await requestWhoopToken({
          grant_type: "authorization_code",
          code,
          redirect_uri: whoopCallbackUrl(),
        });
        await saveWhoopTokens(values.uid, tokens);
        await admin.firestore().collection("users").doc(values.uid).set({
          whoopConnected: true,
          whoopConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return response.redirect(`${_WHOOP_IOS_CALLBACK}?status=success`);
      } catch (error) {
        console.error("[WHOOP] OAuth callback failed", error);
        return fail("WHOOP could not complete authorization.");
      }
    },
);

exports.syncWhoop = onCall(
    {secrets: _WHOOP_SECRETS, timeoutSeconds: 120},
    async (request) => {
      const uid = requireAuth(request);
      const requestedDays = Number(request.data?.daysBack || 30);
      const daysBack = Math.max(1, Math.min(30, Math.floor(requestedDays)));
      const end = new Date();
      const start = new Date(end);
      start.setUTCDate(start.getUTCDate() - daysBack + 1);
      start.setUTCHours(0, 0, 0, 0);

      const [cycles, recoveries, sleeps, workouts, body] = await Promise.all([
        whoopCollection(uid, "/v2/cycle", start, end),
        whoopCollection(uid, "/v2/recovery", start, end),
        whoopCollection(uid, "/v2/activity/sleep", start, end),
        whoopCollection(uid, "/v2/activity/workout", start, end),
        whoopApiRequest(
            uid,
            "/v2/user/measurement/body",
            null,
            true,
        ),
      ]);
      const days = normalizeWhoopData({
        cycles,
        recoveries,
        sleeps,
        workouts,
        body,
      });
      const batch = admin.firestore().batch();
      for (const [day, metrics] of Object.entries(days)) {
        const reference = admin.firestore()
            .collection("users")
            .doc(uid)
            .collection("metrics_daily")
            .doc(day);
        batch.set(reference, {
          ...metrics,
          date: day,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      batch.set(admin.firestore().collection("users").doc(uid), {
        whoopConnected: true,
        lastWhoopSync: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await batch.commit();
      return {
        daysSynced: Object.keys(days).length,
        records: {
          cycles: cycles.length,
          recoveries: recoveries.length,
          sleeps: sleeps.length,
          workouts: workouts.length,
        },
      };
    },
);

exports.disconnectWhoop = onCall(
    {secrets: _WHOOP_SECRETS},
    async (request) => {
      const uid = requireAuth(request);
      const credentials = admin.firestore()
          .collection("whoop_credentials")
          .doc(uid);
      const snapshot = await credentials.get();
      if (snapshot.exists) {
        try {
          await revokeWhoopAccess(uid);
        } catch (error) {
          if (!["unauthenticated", "failed-precondition"]
              .includes(error?.code)) {
            throw error;
          }
          console.info("[WHOOP] remote authorization already inaccessible");
        }
      }

      const batch = admin.firestore().batch();
      batch.delete(credentials);
      batch.set(admin.firestore().collection("users").doc(uid), {
        whoopConnected: false,
        whoopDisconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await batch.commit();
      return {connected: false};
    },
);

exports.beginFitbitConnection = onCall(
    {secrets: [googleHealthClientId]},
    async (request) => {
      const uid = requireAuth(request);
      const state = crypto.randomBytes(32).toString("base64url");
      await admin.firestore()
          .collection("google_health_oauth_states")
          .doc(state)
          .set({
            uid,
            expiresAt: admin.firestore.Timestamp.fromMillis(
                Date.now() + 10 * 60 * 1000,
            ),
          });
      const authorizationUrl = new URL(
          "https://accounts.google.com/o/oauth2/v2/auth",
      );
      authorizationUrl.search = new URLSearchParams({
        response_type: "code",
        client_id: googleHealthClientId.value(),
        redirect_uri: googleHealthCallbackUrl(),
        scope: _GOOGLE_SCOPES.join(" "),
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: "true",
        state,
      }).toString();
      return {authorizationUrl: authorizationUrl.toString()};
    },
);

exports.googleHealthOAuthCallback = onRequest(
    {secrets: _GOOGLE_HEALTH_SECRETS},
    async (request, response) => {
      const state = request.query.state;
      const code = request.query.code;
      const oauthError = request.query.error;
      const fail = (message) => response.redirect(
          `${_IOS_CALLBACK}?error=authorization_failed&` +
          `error_description=${encodeURIComponent(message)}`,
      );
      if (typeof state !== "string") return fail("Missing OAuth state.");
      const reference = admin.firestore()
          .collection("google_health_oauth_states")
          .doc(state);
      const snapshot = await reference.get();
      await reference.delete();
      const values = snapshot.data();
      if (!snapshot.exists ||
          (values?.expiresAt?.toMillis?.() || 0) < Date.now()) {
        return fail("The authorization request expired.");
      }
      if (oauthError || typeof code !== "string") {
        return fail("Google Health authorization was cancelled.");
      }
      try {
        const tokens = await requestGoogleToken({
          grant_type: "authorization_code",
          code,
          redirect_uri: googleHealthCallbackUrl(),
        });
        await saveGoogleHealthTokens(values.uid, tokens);
        await admin.firestore().collection("users").doc(values.uid).set({
          fitbitConnected: true,
          fitbitConnectedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return response.redirect(`${_IOS_CALLBACK}?status=success`);
      } catch (error) {
        console.error("[Google Health] OAuth callback failed", error);
        return fail("Google Health could not complete authorization.");
      }
    },
);

exports.syncFitbit = onCall(
    {secrets: _GOOGLE_HEALTH_SECRETS, timeoutSeconds: 120},
    async (request) => {
      const uid = requireAuth(request);
      const requestedDays = Number(request.data?.daysBack || 30);
      const daysBack = Math.max(1, Math.min(30, Math.floor(requestedDays)));
      const endDate = new Date();
      const startDate = new Date();
      startDate.setUTCDate(endDate.getUTCDate() - daysBack + 1);
      const exclusiveEndDate = new Date(endDate);
      exclusiveEndDate.setUTCDate(exclusiveEndDate.getUTCDate() + 1);

      const accessToken = await getGoogleHealthAccessToken(uid);
      const raw = await fetchGoogleHealthData(
          accessToken,
          startDate,
          exclusiveEndDate,
      );
      const days = normalizeGoogleHealthData(raw);
      addFitbitWellness(days);
      const firestore = admin.firestore();
      const userReference = firestore.collection("users").doc(uid);
      const entries = Object.entries(days);
      const references = entries.map(([day]) => userReference
          .collection("metrics_daily")
          .doc(day));
      // WHOOP is the highest-priority wearable. A transaction makes the
      // decision deterministic even if WHOOP and Fitbit finish syncing at
      // nearly the same time.
      const daysSynced = await firestore.runTransaction(async (transaction) => {
        const snapshots = references.length > 0 ?
          await transaction.getAll(userReference, ...references) :
          [await transaction.get(userReference)];
        const userSnapshot = snapshots[0];
        const existingSnapshots = snapshots.slice(1);
        const whoopConnected =
            userSnapshot.data()?.whoopConnected === true;
        let written = 0;
        for (let index = 0; index < entries.length; index += 1) {
          const [day, metrics] = entries[index];
          const existing = existingSnapshots[index]?.data() || {};
          const resolvedMetrics = {};
          for (const [key, value] of Object.entries(metrics)) {
            const existingSource = existing[key]?.source;
            if (whoopConnected && existingSource === "whoop") continue;
            resolvedMetrics[key] = value;
          }
          if (Object.keys(resolvedMetrics).length === 0) continue;
          transaction.set(references[index], {
            ...resolvedMetrics,
            date: day,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
          written += 1;
        }
        transaction.set(userReference, {
          fitbitConnected: true,
          lastFitbitSync: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        return written;
      });
      return {daysSynced};
    },
);

exports.disconnectFitbit = onCall(
    {secrets: _GOOGLE_HEALTH_SECRETS},
    async (request) => {
      const uid = requireAuth(request);
      const reference =
          admin.firestore().collection("google_health_credentials").doc(uid);
      const snapshot = await reference.get();
      if (snapshot.exists) {
        const token = snapshot.data()?.refreshToken ||
            snapshot.data()?.accessToken;
        if (token) {
          await fetch("https://oauth2.googleapis.com/revoke", {
            method: "POST",
            headers: {
              "Content-Type": "application/x-www-form-urlencoded",
            },
            body: new URLSearchParams({token}),
          }).catch((error) => {
            console.warn("[Google Health] revoke request failed", error);
          });
        }
      }
      await reference.delete();
      await admin.firestore().collection("users").doc(uid).set({
        fitbitConnected: false,
        fitbitDisconnectedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      return {connected: false};
    },
);
/* eslint-enable require-jsdoc */

// =============================================================================
// Batch API helpers
// Model: claude-haiku-4-5-20251001 (cheapest; batch gives additional 50% off)
//
// Workloads:
//   1. weekly-trend-{userId}      nightly
//      → users/{userId}/weekly_trends/{weekOf}
//   2. insight-summary-{userId}   nightly
//      → users/{userId}/insight_summaries/{weekOf}
//   3. questionnaire-{insightId}  on submission
//      → users/{userId}/insights/{insightId}
//
// All batch jobs tracked top-level in batch_jobs/{batchId} — a single nightly
// batch spans many users, so job tracking isn't nested under any one user.
// =============================================================================

const _BATCH_MODEL = "claude-haiku-4-5-20251001";

const _weeklyTrendSystem =
    "You are a health data analyst for Vivordo. You will receive a user's " +
    "heart rate, HRV, steps, and sleep data from the past 7 days as JSON. " +
    "Return ONLY a valid JSON object with two keys: " +
    "\"trend\" (2-3 sentence narrative of the week's patterns) and " +
    "\"actionable\" (one specific, concrete suggestion). " +
    "No prose outside JSON.";

const _insightSummarySystem =
    "You are Panda, a wellness companion. You will receive a user's " +
    "completed wellness check-in sessions from the past 7 days as JSON. " +
    "Return ONLY a valid JSON object with two keys: " +
    "\"summary\" (2-3 sentence overview of recurring themes or patterns) and " +
    "\"highlight\" (the single most significant insight from this week). " +
    "No prose outside JSON.";

// Interprets structured Q→A answers + wellness slots from a single session.
// Output is written back to the originating insight document for the History
// tab and recommendation engine to consume.
const _questionnaireSystem =
    "You are a clinical wellness analyst. You will receive the labeled Q→A " +
    "answers and wellness entity slots from a single Vivordo Panda session. " +
    "Return ONLY a valid JSON object with three keys: " +
    "\"pattern\" (1 sentence — recurring trigger or behavioural pattern " +
    "evident from the answers), " +
    "\"insight\" (1-2 sentences — what the combination of stressor, emotion, " +
    "and context suggests about the user's stress profile), " +
    "\"recommendation\" (1 sentence — one concrete, actionable technique " +
    "tailored to the stressor and intensity). " +
    "No prose outside JSON.";

// =============================================================================
// pandaBatchNightly — workloads 1 & 2 (weekly trend + insight summary)
// =============================================================================

/**
 * Runs at 02:00 PT every night.
 * Queries insights created in the past 7 days, groups by userId, and submits
 * one weekly-trend + one insight-summary batch request per active user.
 * Results are written by pandaBatchPoller once the batch ends.
 */
exports.pandaBatchNightly = onSchedule({
  schedule: "0 2 * * *",
  timeZone: "America/Los_Angeles",
  memory: "256MiB",
  secrets: [anthropicApiKey],
}, async () => {
  const db = admin.firestore();

  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  // insights now lives at users/{userId}/insights — collectionGroup() reaches
  // every user's subcollection in one query.
  const insightsSnap = await db.collectionGroup("insights")
      .where("createdAt", ">=", sevenDaysAgo)
      .get();

  const userInsights = {};
  insightsSnap.forEach((doc) => {
    const data = doc.data();
    if (!data.userId) return;
    if (!userInsights[data.userId]) userInsights[data.userId] = [];
    userInsights[data.userId].push({
      createdAt: data.createdAt?.toDate?.()?.toISOString() ?? null,
      pandaSlots: data.pandaSlots ?? {},
      pandaLabeledAnswers: data.pandaLabeledAnswers ?? {},
      sessionSummary: data.body ?? "",
    });
  });

  const userIds = Object.keys(userInsights);
  if (userIds.length === 0) {
    console.log("[pandaBatchNightly] No active users — skipping.");
    return;
  }

  const requests = [];
  for (const userId of userIds) {
    const sessions = userInsights[userId];

    requests.push({
      custom_id: `weekly-trend-${userId}`,
      params: {
        model: _BATCH_MODEL,
        max_tokens: 512,
        system: [{type: "text", text: _weeklyTrendSystem}],
        messages: [{
          role: "user",
          content: `Weekly sessions:\n${JSON.stringify(sessions, null, 2)}`,
        }],
      },
    });

    requests.push({
      custom_id: `insight-summary-${userId}`,
      params: {
        model: _BATCH_MODEL,
        max_tokens: 256,
        system: [{type: "text", text: _insightSummarySystem}],
        messages: [{
          role: "user",
          content: `Recent sessions:\n${JSON.stringify(sessions, null, 2)}`,
        }],
      },
    });
  }

  const batch = await getAnthropicClient().messages.batches.create({requests});

  await db.collection("batch_jobs").doc(batch.id).set({
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "pending",
    type: "nightly",
    requestCount: requests.length,
    userCount: userIds.length,
  });

  console.log(
      `[pandaBatchNightly] Submitted batch ${batch.id} — ` +
      `${userIds.length} users, ${requests.length} requests.`,
  );
});

// =============================================================================
// pandaQuestionnaireBatch — workload 3 (on session submission)
// =============================================================================

/**
 * Fires when a new `users/{userId}/insights` document is created with
 * source == "panda" and at least one labeled answer present.
 * Submits a single-request Batch API job for deep questionnaire analysis;
 * the result is written back to the same document by pandaBatchPoller.
 */
exports.pandaQuestionnaireBatch = onDocumentCreated(
    {
      document: "users/{userId}/insights/{insightId}",
      secrets: [anthropicApiKey],
    },
    async (event) => {
      const data = event.data?.data();
      if (!data) return;

      // Only process completed Panda sessions that have labeled Q→A answers.
      if (data.source !== "panda") return;
      const answers = data.pandaLabeledAnswers ?? {};
      if (Object.keys(answers).length === 0) return;

      const insightId = event.params.insightId;
      const userId = event.params.userId;
      const db = admin.firestore();

      const payload = {
        pandaSlots: data.pandaSlots ?? {},
        pandaLabeledAnswers: answers,
        sessionDate: data.sessionDate?.toDate?.()?.toISOString() ?? null,
      };

      const batch = await getAnthropicClient().messages.batches.create({
        requests: [{
          custom_id: `questionnaire-${insightId}`,
          params: {
            model: _BATCH_MODEL,
            max_tokens: 384,
            system: [{type: "text", text: _questionnaireSystem}],
            messages: [{
              role: "user",
              content: `Session data:\n${JSON.stringify(payload, null, 2)}`,
            }],
          },
        }],
      });

      // Track the batch so the poller can retrieve and write results.
      await db.collection("batch_jobs").doc(batch.id).set({
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
        type: "questionnaire",
        insightId,
        userId,
      });

      // Stamp the insight doc so the UI can show "analysis pending".
      await event.data.ref.update({
        questionnaireBatchId: batch.id,
        questionnaireAnalysisStatus: "pending",
      });

      console.log(
          `[pandaQuestionnaireBatch] Submitted batch ${batch.id} ` +
          `for insight ${insightId} (user ${userId}).`,
      );
    },
);

// =============================================================================
// pandaBatchPoller — collects results for all three workloads
// =============================================================================

/**
 * Polls every 30 min for completed batch jobs and writes results to Firestore.
 *
 * Routing by custom_id prefix:
 *   weekly-trend-{userId}      → users/{userId}/weekly_trends/{weekOf}
 *   insight-summary-{userId}   → users/{userId}/insight_summaries/{weekOf}
 *   questionnaire-{insightId}
 *     → users/{userId}/insights/{insightId}.questionnaireAnalysis
 *     (userId for the questionnaire route comes from the batch_jobs doc
 *     itself, since unlike the other two, its custom_id only carries the
 *     insightId.)
 */
exports.pandaBatchPoller = onSchedule({
  schedule: "every 30 minutes",
  timeZone: "America/Los_Angeles",
  memory: "256MiB",
  secrets: [anthropicApiKey],
}, async () => {
  const db = admin.firestore();

  const pendingSnap = await db.collection("batch_jobs")
      .where("status", "==", "pending")
      .get();

  if (pendingSnap.empty) return;

  for (const jobDoc of pendingSnap.docs) {
    const batchId = jobDoc.id;

    let batch;
    try {
      batch = await getAnthropicClient().messages.batches.retrieve(batchId);
    } catch (err) {
      console.error(`[pandaBatchPoller] retrieve ${batchId} failed:`, err);
      continue;
    }

    if (batch.processing_status !== "ended") {
      console.log(
          `[pandaBatchPoller] ${batchId} ` +
          `(${batch.processing_status}) — not ready yet.`,
      );
      continue;
    }

    let written = 0;
    const weekOf = new Date().toISOString().split("T")[0];
    const ts = () => admin.firestore.FieldValue.serverTimestamp();
    const jobData = jobDoc.data();

    // Dispatch table — prefix → Firestore write spec.
    // Adding a new batch type = one new entry here, nothing else to touch.
    const routes = [
      {
        prefix: "weekly-trend-",
        // rest = userId
        write: (rest, text) =>
          db.collection("users").doc(rest).collection("weekly_trends")
              .doc(weekOf)
              .set({content: text, generatedAt: ts(), weekOf}, {merge: true}),
      },
      {
        prefix: "insight-summary-",
        // rest = userId
        write: (rest, text) =>
          db.collection("users").doc(rest).collection("insight_summaries")
              .doc(weekOf)
              .set({content: text, generatedAt: ts(), weekOf}, {merge: true}),
      },
      {
        prefix: "questionnaire-",
        // rest = insightId; userId comes from the batch_jobs doc (the
        // custom_id alone doesn't carry it for this workload).
        write: (rest, text) =>
          db.collection("users").doc(jobData.userId)
              .collection("insights").doc(rest).update({
                questionnaireAnalysis: text,
                questionnaireAnalysisStatus: "completed",
                questionnaireAnalyzedAt: ts(),
              }),
      },
    ];

    try {
      for await (const result of
        await getAnthropicClient().messages.batches.results(batchId)) {
        if (result.result.type !== "succeeded") {
          console.warn(
              `[pandaBatchPoller] ${result.custom_id} — ` +
              `result type: ${result.result.type}`,
          );
          continue;
        }

        const text = result.result.message.content?.[0]?.text ?? "";
        const route = routes.find((r) => result.custom_id.startsWith(r.prefix));
        if (!route) continue;
        await route.write(result.custom_id.slice(route.prefix.length), text);
        written++;
      }
    } catch (err) {
      console.error(
          `[pandaBatchPoller] results read failed for ${batchId}:`, err,
      );
      continue;
    }

    await jobDoc.ref.update({status: "completed", resultsWritten: written});
    console.log(
        `[pandaBatchPoller] ${batchId} done — ${written} results written.`,
    );
  }
});
