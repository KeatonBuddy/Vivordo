const {setGlobalOptions} = require("firebase-functions");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const Anthropic = require("@anthropic-ai/sdk");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({maxInstances: 10});

// Single shared client — reused across all function invocations on the same
// container instance (connection pooling, no per-call allocation overhead).
const client = new Anthropic({apiKey: process.env.ANTHROPIC_API_KEY});

// =============================================================================
// pandaClaude — real-time HTTPS Callable proxy for Anthropic API
// Security: API key stays server-side (VIV-309).
// =============================================================================

exports.pandaClaude = onCall(async (request) => {
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

  const msg = await client.messages.create({
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
// Batch API helpers
// Model: claude-haiku-4-5-20251001 (cheapest; batch gives additional 50% off)
//
// Workloads:
//   1. weekly-trend-{userId}      nightly      → weekly_trends/{userId}
//   2. insight-summary-{userId}   nightly      → insight_summaries/{userId}
//   3. questionnaire-{insightId}  on submission → insights/{insightId}
//
// All batch jobs tracked in batch_jobs/{batchId}.
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
}, async () => {
  const db = admin.firestore();

  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const insightsSnap = await db.collection("insights")
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

  const batch = await client.messages.batches.create({requests});

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
 * Fires when a new `insights` document is created with source == "panda"
 * and at least one labeled answer present.
 * Submits a single-request Batch API job for deep questionnaire analysis;
 * the result is written back to the same document by pandaBatchPoller.
 */
exports.pandaQuestionnaireBatch = onDocumentCreated(
    "insights/{insightId}",
    async (event) => {
      const data = event.data?.data();
      if (!data) return;

      // Only process completed Panda sessions that have labeled Q→A answers.
      if (data.source !== "panda") return;
      const answers = data.pandaLabeledAnswers ?? {};
      if (Object.keys(answers).length === 0) return;

      const insightId = event.params.insightId;
      const userId = data.userId;
      const db = admin.firestore();

      const payload = {
        pandaSlots: data.pandaSlots ?? {},
        pandaLabeledAnswers: answers,
        sessionDate: data.sessionDate?.toDate?.()?.toISOString() ?? null,
      };

      const batch = await client.messages.batches.create({
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
 *   weekly-trend-{userId}      → weekly_trends/{userId}
 *   insight-summary-{userId}   → insight_summaries/{userId}
 *   questionnaire-{insightId}  → insights/{insightId}.questionnaireAnalysis
 */
exports.pandaBatchPoller = onSchedule({
  schedule: "every 30 minutes",
  timeZone: "America/Los_Angeles",
  memory: "256MiB",
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
      batch = await client.messages.batches.retrieve(batchId);
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

    // Dispatch table — prefix → Firestore write spec.
    // Adding a new batch type = one new entry here, nothing else to touch.
    const routes = [
      {
        prefix: "weekly-trend-",
        write: (rest, text) =>
          db.collection("weekly_trends").doc(rest)
              .set({content: text, generatedAt: ts(), weekOf}, {merge: true}),
      },
      {
        prefix: "insight-summary-",
        write: (rest, text) =>
          db.collection("insight_summaries").doc(rest)
              .set({content: text, generatedAt: ts(), weekOf}, {merge: true}),
      },
      {
        prefix: "questionnaire-",
        write: (rest, text) =>
          db.collection("insights").doc(rest).update({
            questionnaireAnalysis: text,
            questionnaireAnalysisStatus: "completed",
            questionnaireAnalyzedAt: ts(),
          }),
      },
    ];

    try {
      for await (const result of
        await client.messages.batches.results(batchId)) {
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
