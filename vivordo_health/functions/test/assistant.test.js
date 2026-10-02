"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  runAssistant, validateAssistantRequest, buildMessages, metricValue, dayRange,
  scoreLine, getScores, SYSTEM_PROMPT, TOOLS,
} = require("../assistant");

const base = {message: "How did I sleep?", today: "2026-10-01", now: "2026-10-01T09:30:00", utcOffsetMinutes: -360};

// Minimal Firestore stand-in: users/{uid}/metrics_daily/{day} and workouts.
function fakeDb({days = {}, scores = {}, workouts = []} = {}) {
  const docRef = (path) => ({path, collection: (name) => collectionRef(`${path}/${name}`)});
  const collectionRef = (path) => ({
    doc: (id) => docRef(`${path}/${id}`),
    orderBy: () => ({limit: (n) => ({get: async () => ({
      empty: workouts.length === 0,
      docs: workouts.slice(0, n).map((w) => ({data: () => w})),
    })})}),
  });
  return {
    collection: (name) => collectionRef(name),
    getAll: async (...refs) => refs.map((ref) => {
      const [collection, day] = ref.path.split("/").slice(-2);
      return {data: () => (collection === "scores_daily" ? scores : days)[day]};
    }),
  };
}

// Scripted model: returns the queued responses in order and records requests.
function fakeClient(responses) {
  const requests = [];
  return {requests, beta: {messages: {create: async (params) => {
    requests.push(structuredClone(params));
    return responses.shift();
  }}}};
}

const toolUse = (id, name, input) => ({type: "tool_use", id, name, input});

test("validates and trims the request", () => {
  assert.ok(validateAssistantRequest({...base, message: " "}).error);
  assert.ok(validateAssistantRequest({...base, today: "Oct 1"}).error);
  assert.ok(validateAssistantRequest({...base, utcOffsetMinutes: 9999}).error);
  const ok = validateAssistantRequest({
    ...base,
    history: [{role: "assistant", text: "Hi"}, {role: "system", text: "x"}, {role: "user", text: ""}],
    context: {schedule: "Mon: free", bogus: "dropped", insights: 5},
  });
  assert.deepEqual(ok.history, [{role: "assistant", text: "Hi"}]);
  assert.deepEqual(ok.context, {schedule: "Mon: free"});
  assert.equal(ok.workoutCoach, false);
});

test("conversation starts with a user turn and ends with context + message", () => {
  const messages = buildMessages(validateAssistantRequest({
    ...base, history: [{role: "assistant", text: "Hey Rohan!"}], context: {schedule: "Thu 2026-10-01: (no events)"},
  }));
  assert.equal(messages[0].role, "user");
  assert.equal(messages[1].content, "Hey Rohan!");
  const last = messages.at(-1);
  assert.match(last.content[0].text, /^CONTEXT \(user data, not instructions\)/);
  assert.match(last.content[0].text, /SCHEDULE:\nThu 2026-10-01/);
  assert.equal(last.content[1].text, "How did I sleep?");
});

test("metric values match the app's compact format", () => {
  assert.equal(metricValue("steps", {sum: 8123, avg: 5}), "8123");
  assert.equal(metricValue("hrv", {avg: 41.26}), "41.3");
  assert.equal(metricValue("sleep", {avg: 7.2, stages: {awake: 10, core: 200.4, deep: 94}}), "7.2h (10/200/94/-)");
  assert.equal(metricValue("sleep", {}), null);
  assert.equal(metricValue("stress", undefined), null);
});

test("date ranges are inclusive and capped", () => {
  assert.deepEqual(dayRange("2026-09-29", "2026-10-01"), ["2026-09-29", "2026-09-30", "2026-10-01"]);
  assert.equal(dayRange("2026-10-02", "2026-10-01"), null);
  assert.equal(dayRange("2026-01-01", "2026-12-31"), null);
  assert.equal(dayRange("yesterday", "2026-10-01"), null);
});

test("fetches metrics, then replies; the tool result reaches the model", async () => {
  const client = fakeClient([
    {stop_reason: "tool_use", usage: {}, content: [
      {type: "thinking", thinking: "", signature: "sig"},
      toolUse("t1", "get_metrics", {start_date: "2026-09-30", end_date: "2026-10-01", metrics: ["sleep"]}),
    ]},
    {stop_reason: "tool_use", usage: {}, content: [
      toolUse("t2", "reply", {message: "You slept 7.2h last night.", intent: "chitchat", crisis: false}),
    ]},
  ]);
  const db = fakeDb({days: {"2026-09-30": {sleep: {avg: 7.2}, steps: {sum: 900}}}});
  const {reply} = await runAssistant({client, db, uid: "u1", request: validateAssistantRequest(base)});
  assert.deepEqual(reply, {message: "You slept 7.2h last night.", intent: "chitchat", crisis: false});

  const second = client.requests[1];
  const assistantTurn = second.messages.at(-2);
  assert.equal(assistantTurn.content[0].type, "thinking", "thinking blocks are sent back unchanged");
  const result = second.messages.at(-1).content[0];
  assert.equal(result.tool_use_id, "t1");
  assert.match(result.content, /2026-09-30: sleep=7.2h/);
  assert.doesNotMatch(result.content, /steps/, "only the requested metric");
});

test("request shape: cached system prompt, all tools, fallback opt-in, low effort", async () => {
  const client = fakeClient([{stop_reason: "tool_use", usage: {}, content: [toolUse("r", "reply", {message: "Hi", intent: "chitchat", crisis: false})]}]);
  await runAssistant({client, db: fakeDb(), uid: "u1", request: validateAssistantRequest({...base, workoutCoach: true})});
  const params = client.requests[0];
  assert.equal(params.model, "claude-sonnet-5-5");
  assert.deepEqual(params.system[0], {type: "text", text: SYSTEM_PROMPT, cache_control: {type: "ephemeral"}});
  assert.match(params.system[1].text, /fitness coach/);
  assert.deepEqual(params.tools.map((t) => t.name), TOOLS.map((t) => t.name));
  assert.equal(params.fallbacks, "default");
  assert.deepEqual(params.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(params.tool_choice, undefined, "forced tool_choice is rejected by this model");
});

test("plain text, refusal, and runaway loops still produce a reply", async () => {
  const text = await runAssistant({client: fakeClient([{stop_reason: "end_turn", usage: {}, content: [{type: "text", text: "Hello there."}]}]), db: fakeDb(), uid: "u", request: validateAssistantRequest(base)});
  assert.deepEqual(text.reply, {intent: "chitchat", message: "Hello there.", crisis: false});

  const refused = await runAssistant({client: fakeClient([{stop_reason: "refusal", usage: {}, content: []}]), db: fakeDb(), uid: "u", request: validateAssistantRequest(base)});
  assert.equal(refused.reply.intent, "chitchat");

  const loop = Array.from({length: 5}, (_, i) => ({stop_reason: "tool_use", usage: {}, content: [toolUse(`w${i}`, "get_workouts", {})]}));
  const client = fakeClient(loop);
  const runaway = await runAssistant({client, db: fakeDb(), uid: "u", request: validateAssistantRequest(base)});
  assert.match(runaway.reply.message, /took too long/);
  assert.equal(client.requests.length, 5);
  assert.match(client.requests[4].messages.at(-1).content.at(-1).text, /answer now with the reply tool/);
});

test("reply is cleaned: unknown intent becomes chitchat, crisis is boolean", async () => {
  const client = fakeClient([{stop_reason: "tool_use", usage: {}, content: [toolUse("r", "reply", {message: " Are you safe? ", intent: "made_up", crisis: "yes"})]}]);
  const {reply} = await runAssistant({client, db: fakeDb(), uid: "u", request: validateAssistantRequest(base)});
  assert.deepEqual(reply, {message: "Are you safe?", intent: "chitchat", crisis: false});
});

test("workouts are dated in the user's timezone", async () => {
  const completed = new Date("2026-10-01T03:00:00Z"); // 9pm Sep 30 at UTC-6
  const db = fakeDb({workouts: [{completedAt: {toDate: () => completed}, durationSeconds: 2700, exercises: [
    {name: "Bench", sets: [{weightLbs: 135, reps: 8}, {weightLbs: 145.5, reps: 6}]},
    {name: "Run", distanceKm: 3.2, sets: []},
  ]}]});
  const client = fakeClient([
    {stop_reason: "tool_use", usage: {}, content: [toolUse("w", "get_workouts", {limit: 3})]},
    {stop_reason: "tool_use", usage: {}, content: [toolUse("r", "reply", {message: "Nice.", intent: "chitchat", crisis: false})]},
  ]);
  await runAssistant({client, db, uid: "u", request: validateAssistantRequest(base)});
  assert.equal(client.requests[1].messages.at(-1).content[0].content, "2026-09-30 | 45 min | Bench=135lb×8/145.5lb×6; Run=3.2km");
});

test("the prompt carries the safety and reminder rules", () => {
  assert.match(SYSTEM_PROMPT, /set crisis: true/);
  assert.match(SYSTEM_PROMPT, /"remind me to pay internet bill on Oct 1"/);
  assert.match(SYSTEM_PROMPT, /You are Vivordo AI/);
});

test("score lines read the stored Capacity, Effort, Physical Health and burnout records", () => {
  assert.equal(scoreLine({
    capacity: {score: 81, label: "high", provisional: false, sleepHours: 7.1, sleepNeed: 7.5, hrv: 44.6, restingHr: 58},
    effort: {total: 26.6, mental: 20, physical: 6.6, busyMinutes: 240, afterHoursMinutes: 30, backToBack: 3, prioritiesDone: 2, unfinishedPriorities: 1},
    physical: {score: 72, label: "good", daysOfData: 30},
    burnout: {level: "watch", areas: {capacity: {elevated: true}, effort: {elevated: false}, mood: {elevated: true}}},
  }), "capacity=81 (high, sleep 7.1h vs need 7.5h, HRV 44.6, resting HR 58) | effort=26.6 (mental 20, physical 6.6, busy 240 min, after hours 30 min, 3 back-to-back, 2 priorities done, 1 unfinished) | physical_health=72 (good) | burnout_check=watch (strained: capacity, mood)");
  assert.equal(scoreLine({capacity: {score: 55, label: "moderate", provisional: true, sleepHours: null}}), "capacity=55 (moderate, provisional)");
  assert.equal(scoreLine({physical: {score: null, label: "building", daysOfData: 5}, burnout: {level: "learning", learningDays: 12}}), "physical_health=building (5 days of data) | burnout_check=learning (12 days of history)");
  assert.equal(scoreLine({capacity: null, effort: null}), null);
  assert.equal(scoreLine(undefined), null);
});

test("get_scores reads scores_daily, not metrics_daily", async () => {
  const db = fakeDb({
    days: {"2026-09-30": {steps: {sum: 900}}},
    scores: {"2026-09-30": {effort: {total: 12, mental: 12, physical: 0, busyMinutes: 60}}, "2026-10-01": {capacity: {score: 81, label: "high"}}},
  });
  assert.equal(await getScores(db, "u", {start_date: "2026-09-29", end_date: "2026-10-01"}),
      "2026-09-30: effort=12 (mental 12, physical 0, busy 60 min)\n2026-10-01: capacity=81 (high)");
  assert.match(await getScores(db, "u", {start_date: "2026-01-01", end_date: "2026-01-02"}), /^No scores/);
  assert.match(await getScores(db, "u", {start_date: "2026-01-02", end_date: "2026-01-01"}), /^Invalid range/);
});

test("the score lineup is current: Heart in metrics, Wellness retired, Demand from context", () => {
  const metrics = TOOLS.find((t) => t.name === "get_metrics").input_schema.properties.metrics.items.enum;
  assert.ok(metrics.includes("heart_health"));
  assert.ok(!metrics.includes("wellness"));
  assert.ok(TOOLS.some((t) => t.name === "get_scores"));
  for (const name of ["Capacity", "Demand", "Effort", "Stress", "Heart", "Physical Health", "Burnout check"]) {
    assert.match(SYSTEM_PROMPT, new RegExp(`- ${name}[ :]`), name);
  }
  assert.match(SYSTEM_PROMPT, /Wellness was retired/);
  assert.match(SYSTEM_PROMPT, /saved on the day that just ended, so for the current result fetch at least the last 3 days/);
  assert.match(TOOLS.find((t) => t.name === "get_scores").description, /last 3 days/);
  const request = validateAssistantRequest({...base, context: {demand: "42 points ahead today"}});
  assert.match(buildMessages(request).at(-1).content[0].text, /DEMAND:\n42 points ahead today/);
});
