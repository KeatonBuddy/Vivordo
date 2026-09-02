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
const {
  dueWhoopEndpoints,
  isWhoopAuthorizationFailureCode,
} = require("./whoop_schedule");
const {
  shouldDeleteWhoopSleep,
  whoopDateKey,
  whoopPresentSleepDays,
  whoopReconciliationDays,
} = require("./whoop_reconciliation");
const {
  activityGoalsFromUserData,
  calculateActivityScore,
} = require("./activity_score");
const {
  calculateHeartHealthScore,
  HEART_HEALTH_BASELINE_WINDOW_DAYS,
} = require("./heart_health_score");
const {normalizeGoogleHealthSleep} = require("./google_health_sleep");
const {whoopDeletionPlan} = require("./whoop_deletion");
const {
  challengeDeletionPlan,
  hasRecentAuthentication,
} = require("./account_deletion");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

// Circle challenge callables, progress triggers, and expiration scheduler.
// Loading this module after Firebase Admin initialization keeps all functions
// on the same shared Admin app and Firestore connection pool.
Object.assign(exports, require("./challenges"));

// A distinct Secret Manager binding avoids the legacy plain environment
// variable with the old name on the existing Panda Cloud Run services.
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY_SECRET");
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

async function revokeGoogleHealthAccess(uid) {
  const reference =
      admin.firestore().collection("google_health_credentials").doc(uid);
  const snapshot = await reference.get();
  if (!snapshot.exists) return;
  const token = snapshot.data()?.refreshToken || snapshot.data()?.accessToken;
  if (!token) return;
  const response = await fetch("https://oauth2.googleapis.com/revoke", {
    method: "POST",
    signal: AbortSignal.timeout(15000),
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({token}),
  });
  // Google returns 400 when the token was already invalidated. In that case
  // there is no remaining authorization for Vivordo to revoke.
  if (!response.ok && response.status !== 400) {
    throw new Error(`Google Health revoke failed: ${response.status}`);
  }
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
      dataSourceFamily: "users/me/dataSourceFamilies/google-wearables",
    });
    if (pageToken) query.set("pageToken", pageToken);
    const response = await fetch(
        `${_GOOGLE_HEALTH_API}/users/me/dataTypes/sleep/` +
        `dataPoints:reconcile?${query}`,
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

function normalizeGoogleHealthData(data) {
  const days = {};
  for (const [type, entries] of Object.entries(data)) {
    if (type === "sleep") continue;
    for (const entry of entries) {
      const day = civilDateKey(entry.civilStartTime);
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
  const sleepByDay = normalizeGoogleHealthSleep(data.sleep);
  for (const [day, sleep] of Object.entries(sleepByDay)) {
    const hours = sleep.minutes / 60;
    const sleepMetric = {
      avg: hours,
      min: hours,
      max: hours,
      unit: "hours",
      dimension: "sleep",
      stages: sleep.stages || {},
    };
    if (sleep.bedtime) {
      sleepMetric.bedtime = admin.firestore.Timestamp.fromDate(sleep.bedtime);
    }
    if (sleep.wakeTime) {
      sleepMetric.wakeTime = admin.firestore.Timestamp.fromDate(
          sleep.wakeTime,
      );
    }
    if (sleep.efficiency !== undefined) {
      sleepMetric.efficiency = sleep.efficiency;
    }
    addMetric(days, day, "sleep", sleepMetric);
  }
  return days;
}

function importedHeartHealthSignals(metrics = {}) {
  const valid = (value) => Number.isFinite(value) && value > 0 ? value : null;
  return {
    restingHeartRate: valid(metrics.resting_heart_rate?.avg),
    hrvSdnn: valid(metrics.hrv?.avg),
    quietHeartRate: valid(metrics.heart_rate_scan?.avg) ??
      valid(metrics.heart_rate?.min),
  };
}

function addFitbitWellness(days, activityGoals) {
  const dates = Object.keys(days).sort();
  for (let dateIndex = 0; dateIndex < dates.length; dateIndex++) {
    const metrics = days[dates[dateIndex]];
    let weightedScore = 0;
    let totalWeight = 0;
    const sleep = metrics.sleep?.avg;
    const steps = metrics.steps?.sum;
    const exerciseMinutes = metrics.exercise_time?.sum;
    const activeCalories = metrics.active_calories?.sum;
    const activity = calculateActivityScore({
      steps,
      exerciseMinutes,
      activeCalories,
      stepsGoal: activityGoals.steps,
      exerciseMinutesGoal: activityGoals.exerciseMinutes,
      activeCaloriesGoal: activityGoals.activeCalories,
    });
    const historyStart = Math.max(
        0,
        dateIndex - HEART_HEALTH_BASELINE_WINDOW_DAYS,
    );
    const heartHealth = calculateHeartHealthScore(
        importedHeartHealthSignals(metrics),
        dates.slice(historyStart, dateIndex)
            .map((date) => importedHeartHealthSignals(days[date])),
    );
    if (Number.isFinite(sleep)) {
      weightedScore += Math.max(0, Math.min(100, sleep / 8 * 100)) * 0.30;
      totalWeight += 30;
    }
    if (activity !== null) {
      weightedScore += activity.score * 0.20;
      totalWeight += 20;
    }
    if (heartHealth.score !== null) {
      weightedScore += heartHealth.score * 0.15;
      totalWeight += 15;
    }
    metrics.heart_health = {
      avg: heartHealth.score,
      unit: "score",
      source: "computed_personal_baseline",
      status: heartHealth.isBuildingBaseline ?
        "building_baseline" : heartHealth.score === null ?
          "unavailable" : "ready",
      confidence: heartHealth.confidence,
      availableSignals: heartHealth.availableSignals,
      scoredSignals: heartHealth.scoredSignals,
      baselineDays: heartHealth.baselineDays,
      components: {
        restingHeartRate: heartHealth.restingHeartRateScore,
        hrv: heartHealth.hrvScore,
        quietHeartRate: heartHealth.quietHeartRateScore,
      },
      computedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
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
  "read:sleep",
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

async function invalidateWhoopAuthorization(uid) {
  const firestore = admin.firestore();
  const batch = firestore.batch();
  batch.delete(firestore.collection("whoop_credentials").doc(uid));
  batch.set(firestore.collection("users").doc(uid), {
    whoopConnected: false,
    whoopAuthorizationExpiredAt:
        admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
}

async function throwWhoopReconnectRequired(uid, error) {
  if (!isWhoopAuthorizationFailureCode(error?.code)) return;
  try {
    await invalidateWhoopAuthorization(uid);
  } catch (stateError) {
    console.error(
        "[WHOOP] failed to persist expired authorization state",
        stateError,
    );
  }
  throw new HttpsError(
      "failed-precondition",
      "WHOOP authorization has expired. Reconnect WHOOP.",
      {whoopReconnectRequired: true},
  );
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

/**
 * Atomically selects the WHOOP endpoints due for one sync invocation.
 * Endpoint leases prevent overlapping app lifecycle calls from duplicating
 * the same WHOOP requests.
 *
 * @param {string} uid Firebase user id.
 * @param {boolean} force Whether this is an explicit user refresh.
 * @param {number} timezoneOffsetMinutes User-local UTC offset in minutes.
 * @return {Promise<Object>} Claimed endpoints and their schedule slot.
 */
async function claimWhoopSync(uid, force, timezoneOffsetMinutes) {
  const reference = admin.firestore()
      .collection("whoop_credentials")
      .doc(uid);
  const nowMs = Date.now();
  const claimId = crypto.randomBytes(16).toString("hex");
  return admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      throw new HttpsError(
          "failed-precondition",
          "Connect WHOOP before syncing.",
      );
    }
    const credentials = snapshot.data() || {};
    const state = credentials.syncState || {};
    const schedule = dueWhoopEndpoints({
      nowMs,
      force,
      timezoneOffsetMinutes,
      lastSleepMorningDate: state.lastSleepMorningDate,
      lastSleepMiddayDate: state.lastSleepMiddayDate,
    });
    const leases = credentials.syncLeases || {};
    const leaseAvailable = (endpoint) =>
      (endpoint?.expiresAt?.toMillis?.() || 0) <= nowMs;
    const sleep = schedule.sleep && leaseAvailable(leases.sleep);
    if (sleep) {
      const expiresAt = admin.firestore.Timestamp.fromMillis(
          nowMs + 2 * 60 * 1000,
      );
      const nextLeases = {...leases};
      if (sleep) nextLeases.sleep = {id: claimId, expiresAt};
      transaction.set(reference, {syncLeases: nextLeases}, {merge: true});
    }
    return {
      reference,
      claimId,
      sleep,
      localDate: schedule.localDate,
      sleepSlot: schedule.sleepSlot,
    };
  });
}

/**
 * Releases endpoint leases and advances only schedules whose data was saved.
 *
 * @param {Object} claim Claim returned by claimWhoopSync.
 * @param {Object} succeeded Per-endpoint save results.
 * @return {Promise<void>}
 */
async function finishWhoopSync(claim, succeeded) {
  if (!claim.sleep) return;
  await admin.firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(claim.reference);
    if (!snapshot.exists) return;
    const leases = snapshot.data()?.syncLeases || {};
    const updates = {};
    if (claim.sleep && leases.sleep?.id === claim.claimId) {
      updates["syncLeases.sleep"] = admin.firestore.FieldValue.delete();
      if (succeeded.sleep &&
          ["morning", "midday"].includes(claim.sleepSlot)) {
        const slot = claim.sleepSlot === "morning" ? "Morning" : "Midday";
        updates[`syncState.lastSleep${slot}Date`] = claim.localDate;
      }
    }
    if (Object.keys(updates).length > 0) {
      transaction.update(claim.reference, updates);
    }
  });
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

function normalizeWhoopData({sleeps}) {
  const days = {};
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
  }
  return days;
}

async function saveAndReconcileWhoopSleep(
    uid,
    days,
    sleeps,
    claim,
    daysBack,
) {
  const firestore = admin.firestore();
  const userReference = firestore.collection("users").doc(uid);
  const metricsCollection = userReference.collection("metrics_daily");
  const presentDays = whoopPresentSleepDays(sleeps);
  const reconciliationDays = whoopReconciliationDays({
    localDate: claim.localDate,
    daysBack,
    includeCurrentDay: claim.sleepSlot === "midday",
  });
  const reconciliationReferences = reconciliationDays.map(
      (day) => metricsCollection.doc(day),
  );

  return firestore.runTransaction(async (transaction) => {
    const existingSnapshots = reconciliationReferences.length > 0 ?
      await transaction.getAll(...reconciliationReferences) : [];
    let removed = 0;
    for (let index = 0; index < reconciliationDays.length; index += 1) {
      const day = reconciliationDays[index];
      const snapshot = existingSnapshots[index];
      const existingSleep = snapshot.data()?.sleep;
      if (!snapshot.exists || !shouldDeleteWhoopSleep(
          existingSleep,
          presentDays.has(day),
      )) {
        continue;
      }
      transaction.update(reconciliationReferences[index], {
        sleep: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      removed += 1;
    }

    for (const [day, metrics] of Object.entries(days)) {
      transaction.set(metricsCollection.doc(day), {
        ...metrics,
        date: day,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.set(userReference, {
      whoopConnected: true,
      lastWhoopSync: admin.firestore.FieldValue.serverTimestamp(),
      lastWhoopSleepSync: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    return removed;
  });
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
      const rawRequestedDays = Number(request.data?.daysBack || 30);
      const requestedDays = Number.isFinite(rawRequestedDays) ?
        rawRequestedDays : 30;
      const daysBack = Math.max(1, Math.min(30, Math.floor(requestedDays)));
      const force = request.data?.force === true;
      const timezoneOffsetMinutes =
        Number(request.data?.timezoneOffsetMinutes || 0);
      let claim;
      try {
        claim = await claimWhoopSync(
            uid,
            force,
            timezoneOffsetMinutes,
        );
      } catch (error) {
        await throwWhoopReconnectRequired(uid, error);
        throw error;
      }
      if (!claim.sleep) {
        return {
          daysSynced: 0,
          records: {sleeps: 0},
          endpoints: {sleep: "not_due"},
        };
      }

      // Scheduled refreshes need only the current/previous local day. Explicit
      // user refreshes retain the requested history window.
      const effectiveDaysBack = force ? daysBack : 2;
      const end = new Date();
      const start = new Date(end);
      // Fetch one extra UTC day so timezone boundaries cannot make the oldest
      // local reconciliation day look falsely absent.
      start.setUTCDate(start.getUTCDate() - effectiveDaysBack);
      start.setUTCHours(0, 0, 0, 0);

      try {
        const sleeps = await whoopCollection(
            uid,
            "/v2/activity/sleep",
            start,
            end,
        );
        const days = normalizeWhoopData({sleeps});
        const sleepRemoved = await saveAndReconcileWhoopSleep(
            uid,
            days,
            sleeps,
            claim,
            effectiveDaysBack,
        );
        await finishWhoopSync(claim, {sleep: true});
        return {
          daysSynced: Object.keys(days).length,
          sleepRemoved,
          records: {sleeps: sleeps.length},
          endpoints: {sleep: "synced"},
        };
      } catch (error) {
        await finishWhoopSync(claim, {sleep: false});
        await throwWhoopReconnectRequired(uid, error);
        if (error instanceof HttpsError) throw error;
        console.error("[WHOOP] sleep sync failed", error);
        throw new HttpsError(
            "unavailable",
            "WHOOP could not be synced. Please try again.",
        );
      }
    },
);

/**
 * Deletes imported WHOOP measurements while preserving other providers in the
 * same daily documents. Kept separate so full account deletion can invoke the
 * same cleanup before removing the user tree.
 *
 * @param {string} uid Authenticated Firebase user ID.
 * @return {Promise<number>} Number of affected daily documents.
 */
async function deleteWhoopImportedData(uid) {
  const firestore = admin.firestore();
  const userReference = firestore.collection("users").doc(uid);
  await userReference.set({
    whoopDataDeletionStatus: "pending",
    whoopDataDeletionStartedAt:
      admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  try {
    const metrics = await userReference.collection("metrics_daily").get();
    const writer = firestore.bulkWriter();
    let affectedDays = 0;
    for (const document of metrics.docs) {
      const plan = whoopDeletionPlan(document.data());
      if (!plan.changed) continue;
      const update = {
        ...plan.setFields,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      for (const path of plan.deletePaths) {
        update[path] = admin.firestore.FieldValue.delete();
      }
      writer.update(document.ref, update);
      affectedDays += 1;
    }
    await writer.close();
    await userReference.set({
      whoopImportedDataRetained: false,
      whoopDataDeletionStatus: "complete",
      whoopDataDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
      whoopDataDeletionAffectedDays: affectedDays,
    }, {merge: true});
    return affectedDays;
  } catch (error) {
    await userReference.set({
      whoopDataDeletionStatus: "failed",
      whoopDataDeletionFailedAt:
        admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    throw error;
  }
}

exports.disconnectWhoop = onCall(
    {secrets: _WHOOP_SECRETS},
    async (request) => {
      const uid = requireAuth(request);
      const deleteImportedData = request.data?.deleteImportedData === true;
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
        whoopImportedDataRetained: deleteImportedData ? null : true,
        whoopDataDeletionStatus: deleteImportedData ?
          "pending" : "not_requested",
      }, {merge: true});
      await batch.commit();
      const affectedDays = deleteImportedData ?
        await deleteWhoopImportedData(uid) : 0;
      return {
        connected: false,
        importedDataDeleted: deleteImportedData,
        affectedDays,
      };
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
      const firestore = admin.firestore();
      const userReference = firestore.collection("users").doc(uid);
      const activityGoalsSnapshot = await userReference.get();
      addFitbitWellness(
          days,
          activityGoalsFromUserData(activityGoalsSnapshot.data()),
      );
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

async function deleteQueryDocuments(query) {
  const snapshot = await query.get();
  if (snapshot.empty) return 0;
  const writer = admin.firestore().bulkWriter();
  for (const document of snapshot.docs) writer.delete(document.ref);
  await writer.close();
  return snapshot.size;
}

async function deleteCircleRelationships(uid) {
  const db = admin.firestore();
  const friends = await db.collection("users").doc(uid)
      .collection("circle").doc("relationships")
      .collection("friends").get();
  if (!friends.empty) {
    const writer = db.bulkWriter();
    for (const friend of friends.docs) {
      const friendUid = friend.data()?.uid || friend.id;
      if (typeof friendUid !== "string" || !friendUid) continue;
      writer.delete(db.collection("users").doc(friendUid)
          .collection("circle").doc("relationships")
          .collection("friends").doc(uid));
    }
    await writer.close();
  }
}

async function deleteUserChallenges(uid) {
  const db = admin.firestore();
  const challenges = await db.collection("challenges")
      .where("participantUids", "array-contains", uid).get();
  for (const challengeDocument of challenges.docs) {
    const challengeReference = challengeDocument.ref;
    const outcome = await db.runTransaction(async (transaction) => {
      const challengeSnapshot = await transaction.get(challengeReference);
      if (!challengeSnapshot.exists) return null;
      const participantReference = challengeReference
          .collection("participants").doc(uid);
      const participantSnapshot = await transaction.get(participantReference);
      const participantProgress = participantSnapshot.data()?.progress || 0;
      const plan = challengeDeletionPlan(
          challengeSnapshot.data(),
          uid,
          participantProgress,
      );
      if (plan.deleteChallenge) return plan;

      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.update(challengeReference, {...plan.update, updatedAt: now});
      transaction.delete(participantReference);
      for (const remainingUid of plan.remainingParticipantUids) {
        const membership = db.collection("challenge_memberships")
            .doc(remainingUid).collection("items")
            .doc(challengeReference.id);
        const update = {
          participantUids: plan.remainingParticipantUids,
          participantCount: plan.remainingParticipantUids.length,
          creatorUid: plan.update.creatorUid,
          creatorName: plan.update.creatorName,
          updatedAt: now,
        };
        if (plan.update.status === "cancelled") {
          update.status = "cancelled";
        }
        if (remainingUid === plan.newCreatorUid) {
          update.role = "creator";
          if (plan.update.status !== "cancelled") update.status = "waiting";
        }
        transaction.set(membership, update, {merge: true});
      }
      if (plan.newCreatorUid) {
        const participantUpdate = {role: "creator", updatedAt: now};
        if (plan.newCreatorWasPending) {
          participantUpdate.status = "accepted";
          participantUpdate.acceptedAt = now;
        }
        transaction.set(challengeReference.collection("participants")
            .doc(plan.newCreatorUid), participantUpdate, {merge: true});
      }
      return plan;
    });
    if (outcome?.deleteChallenge) {
      await db.recursiveDelete(challengeReference);
    }
  }
}

async function deleteGlobalUserReferences(uid) {
  const db = admin.firestore();
  const queries = [
    db.collection("circle_usernames").where("uid", "==", uid),
    db.collection("circle_friend_codes").where("uid", "==", uid),
    db.collection("whoop_oauth_states").where("uid", "==", uid),
    db.collection("google_health_oauth_states").where("uid", "==", uid),
    db.collection("goals").where("userId", "==", uid),
    db.collection("metrics_daily").where("userId", "==", uid),
    db.collection("questionnaire_responses").where("userId", "==", uid),
    db.collection("questionaire_responses").where("userId", "==", uid),
    db.collection("insights").where("userId", "==", uid),
    db.collection("bug_reports").where("userId", "==", uid),
    db.collection("batch_jobs").where("userId", "==", uid),
    db.collectionGroup("friend_requests").where("fromUid", "==", uid),
    db.collectionGroup("comments").where("authorUid", "==", uid),
    db.collectionGroup("likes").where("userUid", "==", uid),
    db.collectionGroup("contributions").where("uid", "==", uid),
    db.collectionGroup("circle_engagement").where("actorUid", "==", uid),
  ];
  for (const query of queries) await deleteQueryDocuments(query);
}

async function revokeConnectedProviders(uid) {
  const db = admin.firestore();
  const whoopCredentials = db.collection("whoop_credentials").doc(uid);
  const googleCredentials = db.collection("google_health_credentials").doc(uid);
  const [whoopSnapshot, googleSnapshot] = await Promise.all([
    whoopCredentials.get(),
    googleCredentials.get(),
  ]);
  if (whoopSnapshot.exists) {
    await revokeWhoopAccess(uid);
  }
  if (googleSnapshot.exists) {
    await revokeGoogleHealthAccess(uid);
  }
  await Promise.all([whoopCredentials.delete(), googleCredentials.delete()]);
}

async function deleteVivordoAccountData(uid) {
  const db = admin.firestore();
  await revokeConnectedProviders(uid);
  await deleteCircleRelationships(uid);
  await deleteUserChallenges(uid);
  await deleteGlobalUserReferences(uid);
  await Promise.all([
    db.recursiveDelete(db.collection("challenge_memberships").doc(uid)),
    db.recursiveDelete(db.collection("challenge_medal_awards").doc(uid)),
  ]);
  await admin.storage().bucket().deleteFiles({
    prefix: `circle_profiles/${uid}/`,
  });
  await db.recursiveDelete(db.collection("users").doc(uid));
}

exports.deleteVivordoAccount = onCall(
    {
      secrets: [..._WHOOP_SECRETS, ..._GOOGLE_HEALTH_SECRETS],
      timeoutSeconds: 540,
      memory: "512MiB",
    },
    async (request) => {
      const uid = requireAuth(request);
      if (request.data?.confirmation !== "DELETE") {
        throw new HttpsError(
            "invalid-argument",
            "Type DELETE to confirm permanent account deletion.",
        );
      }
      if (!hasRecentAuthentication(request.auth)) {
        throw new HttpsError(
            "failed-precondition",
            "Sign in again before deleting your account.",
        );
      }

      const db = admin.firestore();
      const deletionId = crypto.createHash("sha256").update(uid).digest("hex");
      const deletionJob = db.collection("account_deletion_jobs")
          .doc(deletionId);
      await deletionJob.set({
        status: "deleting",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      await admin.auth().updateUser(uid, {disabled: true});
      try {
        await deleteVivordoAccountData(uid);
        await admin.auth().deleteUser(uid);
        await deletionJob.set({
          status: "complete",
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          error: admin.firestore.FieldValue.delete(),
        }, {merge: true});
        return {deleted: true};
      } catch (error) {
        console.error("[Account deletion] failed", {uid, error});
        try {
          await admin.auth().updateUser(uid, {disabled: false});
        } catch (restoreError) {
          if (restoreError?.code !== "auth/user-not-found") {
            console.error("[Account deletion] could not restore user", {
              uid,
              restoreError,
            });
          }
        }
        await deletionJob.set({
          status: "failed",
          failedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          error: "cleanup_failed",
        }, {merge: true});
        throw new HttpsError(
            "internal",
            "Your account could not be deleted. Please try again.",
        );
      }
    },
);

exports.disconnectFitbit = onCall(
    {secrets: _GOOGLE_HEALTH_SECRETS},
    async (request) => {
      const uid = requireAuth(request);
      const reference =
          admin.firestore().collection("google_health_credentials").doc(uid);
      await revokeGoogleHealthAccess(uid).catch((error) => {
        console.warn("[Google Health] revoke request failed", error);
      });
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
