"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  runAssistant, validateAssistantRequest, buildMessages, metricValue, dayRange,
  scoreLine, getScores, planMemoryChange, loadThread, getPriorities, planPriority,
  planCalendar, visibleOnDay, chartBlock, sourceBlocks, SYSTEM_PROMPT, TOOLS, saveMessages,
} = require("../assistant");

const base = {message: "How did I sleep?", today: "2026-10-01", now: "2026-10-01T09:30:00", utcOffsetMinutes: -360};

// Minimal Firestore stand-in: users/{uid}/metrics_daily/{day} and workouts.
function fakeDb({days = {}, scores = {}, workouts = [], memory = [], conversations = [], messages = [], docs = {}} = {}) {
  const writes = [];
  let nextId = 0;
  const lists = {workouts, memory, conversations, messages};
  const snap = (path) => ({id: path.split("/").pop(), exists: path in docs, data: () => docs[path]});
  const docRef = (path) => ({path, id: path.split("/").pop(), collection: (name) => collectionRef(`${path}/${name}`),
    get: async () => snap(path)});
  const query = (path, filters) => ({
    where: (field, op, value) => query(path, [...filters, (d) => d[field] === value]),
    get: async () => {
      const found = Object.keys(docs).filter((p) => p.startsWith(`${path}/`) && !p.slice(path.length + 1).includes("/"))
          .filter((p) => filters.every((f) => f(docs[p]))).map(snap);
      return {empty: found.length === 0, docs: found};
    },
  });
  const collectionRef = (path) => ({
    ...query(path, []),
    doc: (id) => docRef(`${path}/${id ?? `new${nextId++}`}`),
    orderBy: () => ({limit: (n) => ({get: async () => {
      const list = lists[path.split("/").pop()] ?? [];
      return {empty: list.length === 0, docs: list.slice(0, n).map((item) => ({
        id: item.id, data: () => item.data ?? item,
      }))};
    }})}),
  });
  return {
    writes,
    collection: (name) => collectionRef(name),
    getAll: async (...refs) => refs.map((ref) => {
      const [collection, day] = ref.path.split("/").slice(-2);
      return {data: () => (collection === "scores_daily" ? scores : days)[day]};
    }),
    batch: () => {
      const pending = [];
      return {
        set: (ref, data, options) => pending.push({op: options?.merge ? "merge" : "set", path: ref.path, data}),
        delete: (ref) => pending.push({op: "delete", path: ref.path}),
        commit: async () => writes.push(...pending),
      };
    },
  };
}

// Memory and summary writes, without the two thread messages every turn adds.
const memoryWrites = (db) => db.writes.filter((w) => !w.path.includes("/messages/"));
// A reply without the conversation id the server assigns.
const withoutThread = ({conversationId: _id, ...rest}) => rest;

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
  assert.deepEqual(withoutThread(reply), {message: "You slept 7.2h last night.", intent: "chitchat", crisis: false, suggestions: [],
    blocks: [{type: "text", text: "You slept 7.2h last night."},
      {type: "source", label: "Sleep", screen: "sleep", start: "2026-09-30", end: "2026-10-01"}]});

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
  assert.deepEqual(withoutThread(text.reply), {intent: "chitchat", message: "Hello there.", crisis: false, suggestions: [],
    blocks: [{type: "text", text: "Hello there."}]});

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
  assert.deepEqual(withoutThread(reply), {message: "Are you safe?", intent: "chitchat", crisis: false, suggestions: [],
    blocks: [{type: "text", text: "Are you safe?"}]});
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
  assert.match(SYSTEM_PROMPT, /never repeat or paraphrase self-harm, suicidal or abuse details in the summary/);
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
  await assert.rejects(getScores(db, "u", {start_date: "2026-01-02", end_date: "2026-01-01"}), /^Error: Invalid range/);
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

const now = () => "TS";
const at = (iso) => ({toDate: () => new Date(iso)});

test("memory changes are checked before anything is written", () => {
  const state = {facts: [{id: "f1", kind: "helps", text: "Finds walks calming"}], pending: []};
  assert.deepEqual(planMemoryChange({action: "add", kind: "stressor", text: " Deadlines at work "}, state),
      {op: {action: "add", kind: "stressor", text: "Deadlines at work"}, result: "Saved."});
  assert.equal(planMemoryChange({action: "add", kind: "made_up", text: "x"}, state).op.kind, "context");
  assert.match(planMemoryChange({action: "add", text: "x".repeat(201)}, state).result, /^Not saved/);
  assert.match(planMemoryChange({action: "update", id: "nope", text: "x"}, state).result, /unknown id/);
  assert.deepEqual(planMemoryChange({action: "update", id: "f1", text: "Finds long walks calming"}, state).op,
      {action: "update", id: "f1", text: "Finds long walks calming"});
  assert.deepEqual(planMemoryChange({action: "forget", id: "f1"}, state).op, {action: "forget", id: "f1"});
  assert.match(planMemoryChange({action: "rename"}, state).result, /must be add, update or forget/);
  const full = {facts: Array.from({length: 100}, (_, i) => ({id: `f${i}`, kind: "context", text: "x"})), pending: []};
  assert.match(planMemoryChange({action: "add", text: "one more"}, full).result, /memory is full/);
  full.pending.push({action: "forget", id: "f0"});
  assert.ok(planMemoryChange({action: "add", text: "one more"}, full).op, "forgetting makes room");
});

test("the model sees what it remembers and recent chats, then saves a fact and the summary", async () => {
  const db = fakeDb({
    memory: [{id: "f1", data: {kind: "helps", text: "Finds short walks calming", updatedAt: at("2026-09-30T12:00:00Z")}}],
    conversations: [
      {id: "chat-now", data: {summary: "Talked about the pitch deck.", updatedAt: at("2026-10-01T20:00:00Z")}},
      {id: "chat-old", data: {summary: "Planned a lighter Friday.", updatedAt: at("2026-09-29T15:00:00Z")}},
    ],
  });
  const client = fakeClient([
    {stop_reason: "tool_use", usage: {}, content: [toolUse("m1", "save_memory", {action: "add", kind: "stressor", text: "Deadlines at work"})]},
    {stop_reason: "tool_use", usage: {}, content: [toolUse("r", "reply", {message: "That sounds heavy.", intent: "chitchat", crisis: false, summary: "Shared that work deadlines are stressful."})]},
  ]);
  const result = await runAssistant({client, db, uid: "u1", now, request: validateAssistantRequest({...base, conversationId: "chat-now"})});
  assert.equal(result.memoryChanges, 1);

  const context = client.requests[0].messages.at(-1).content[0].text;
  assert.match(context, /WHAT YOU REMEMBER \(id \| kind \| fact\):\nf1 \| helps \| Finds short walks calming/);
  assert.match(context, /RECENT CONVERSATIONS:\n2026-09-29: Planned a lighter Friday\./);
  const recent = context.split("\n\n").find((part) => part.startsWith("RECENT CONVERSATIONS"));
  assert.doesNotMatch(recent, /pitch deck/, "the current chat isn't a 'recent' one");
  assert.match(context, /THIS CONVERSATION SO FAR \(earlier summary\): Talked about the pitch deck\./);
  assert.equal(client.requests[1].messages.at(-1).content[0].content, "Saved.");

  assert.deepEqual(memoryWrites(db), [
    {op: "set", path: "users/u1/memory/new0", data: {kind: "stressor", text: "Deadlines at work", source: "chat", conversationId: "chat-now", createdAt: "TS", updatedAt: "TS"}},
    {op: "merge", path: "users/u1/conversations/chat-now", data: {summary: "Shared that work deadlines are stressful.", updatedAt: "TS", day: "2026-10-01"}},
  ]);
});

test("a crisis turn saves no facts, and memory saved alongside the reply counts", async () => {
  const crisisDb = fakeDb();
  await runAssistant({client: fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("m", "save_memory", {action: "add", kind: "context", text: "Feels everyone is better off without them"}),
    toolUse("r", "reply", {message: "Are you safe right now?", intent: "chitchat", crisis: true, summary: "A hard moment; support was offered."}),
  ]}]), db: crisisDb, uid: "u", now, request: validateAssistantRequest({...base, conversationId: "c1"})});
  assert.deepEqual(memoryWrites(crisisDb).map((w) => w.path), ["users/u/conversations/c1"]);
  assert.equal(memoryWrites(crisisDb)[0].data.summary, "A hard moment came up and support was offered.",
      "the model's own summary of a crisis turn is never stored");

  const ongoing = fakeDb({conversations: [{id: "c2", data: {summary: "Planned a calmer week.", updatedAt: at("2026-10-01T20:00:00Z")}}]});
  await runAssistant({client: fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("r", "reply", {message: "Are you safe right now?", intent: "chitchat", crisis: true, summary: "User shared thoughts of self-harm."}),
  ]}]), db: ongoing, uid: "u", now, request: validateAssistantRequest({...base, conversationId: "c2"})});
  assert.equal(memoryWrites(ongoing)[0].data.summary, "Planned a calmer week. A hard moment came up and support was offered.");

  const sameTurnDb = fakeDb({memory: [{id: "old", data: {kind: "helps", text: "Likes running"}}]});
  await runAssistant({client: fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("m", "save_memory", {action: "forget", id: "old"}),
    toolUse("r", "reply", {message: "Done, I've forgotten that.", intent: "chitchat", crisis: false, summary: "Asked to forget running."}),
  ]}]), db: sameTurnDb, uid: "u", now, request: validateAssistantRequest(base)});
  assert.deepEqual(memoryWrites(sameTurnDb).map((w) => `${w.op} ${w.path.replace(/c\d+$/, "c…")}`),
      ["delete users/u/memory/old", "merge users/u/conversations/c…"], "a conversation always exists now");
});

test("conversation ids are validated", () => {
  assert.equal(validateAssistantRequest({...base, conversationId: "2026-10-01T20:15:03.123456"}).conversationId, "2026-10-01T20:15:03.123456");
  assert.equal(validateAssistantRequest({...base, conversationId: "a/b"}).conversationId, null);
  assert.equal(validateAssistantRequest({...base, conversationId: "x".repeat(65)}).conversationId, null);
});

const items = (day) => `users/u/daily_priorities/${day}/items`;

test("visibleOnDay matches My Day: open untimed manual priorities carry over", () => {
  const manual = {source: "manual", completed: false};
  assert.equal(visibleOnDay(manual, "2026-09-24", "2026-10-01"), true);
  assert.equal(visibleOnDay({...manual, completed: true, completedDay: "2026-09-30"}, "2026-09-24", "2026-10-01"), false);
  assert.equal(visibleOnDay({...manual, completed: true, completedDay: "2026-10-01"}, "2026-09-24", "2026-10-01"), true);
  assert.equal(visibleOnDay({...manual, sourceStart: {}}, "2026-09-24", "2026-10-01"), false, "timed ones stay on their day");
  assert.equal(visibleOnDay({source: "calendar"}, "2026-09-24", "2026-10-01"), false);
  assert.equal(visibleOnDay(manual, "2026-10-03", "2026-10-01"), false, "future ones aren't shown early");
  assert.equal(visibleOnDay({...manual, planning: {plannedDay: "2026-10-01"}}, "2026-10-03", "2026-10-01"), true);
  assert.equal(visibleOnDay({...manual, dismissed: true}, "2026-10-01", "2026-10-01"), false);
});

test("get_priorities lists the range plus open carry-overs, with ids", async () => {
  const db = fakeDb({docs: {
    "users/u": {priorityReminderDays: ["2026-09-24", "2026-10-03", "2026-08-01"]},
    [`${items("2026-09-24")}/deck`]: {title: "Finalize pitch deck", source: "manual", completed: false, planning: {minutes: 30, effort: "moderate", estimated: true}},
    [`${items("2026-08-01")}/old`]: {title: "Old done thing", source: "manual", completed: true, completedDay: "2026-08-02"},
    [`${items("2026-10-03")}/dentist`]: {title: "Call the dentist", source: "manual", completed: false, reminderTimeMinutes: 540},
    [`${items("2026-10-02")}/standup`]: {title: "Standup", source: "calendar", sourceEventKey: "k", isAllDay: false,
      sourceStart: at("2026-10-02T15:00:00Z"), completed: false},
    [`${items("2026-10-02")}/gone`]: {title: "Dismissed", source: "manual", dismissed: true},
  }});
  const result = await getPriorities(db, "u", {start_date: "2026-10-01", end_date: "2026-10-03"}, -360);
  assert.equal(result, [
    "id=2026-09-24/deck | Finalize pitch deck | open, 2026-09-24, no time, carried over from 2026-09-24, effort moderate, ~30 min (estimated)",
    "id=2026-10-02/standup | Standup | open, scheduled 2026-10-02 09:00, from calendar",
    "id=2026-10-03/dentist | Call the dentist | open, 2026-10-03, no time, reminder 09:00",
  ].join("\n"));
  assert.match(await getPriorities(db, "u", {start_date: "2026-01-01", end_date: "2026-01-02"}, 0), /^No priorities/);
});

const req = (extra = {}) => validateAssistantRequest({...base, now: "2026-10-01T21:00:00", ...extra});

test("propose_priority: creates are checked like the app's PandaPriorityAction", async () => {
  const db = fakeDb();
  assert.deepEqual(await planPriority(db, "u", {operation: "create", title: "Call the dentist", date: "2026-10-03"}, req()),
      {action: {type: "priority", operation: "create", title: "Call the dentist", date: "2026-10-03"},
        result: "Proposed: add \"Call the dentist\" on 2026-10-03. The app will ask the user to confirm."});
  const reject = async (input, pattern) =>
    assert.match((await planPriority(db, "u", {operation: "create", title: "x", ...input}, req())).result, pattern);
  await reject({title: ""}, /title must be/);
  await reject({date: "2026-02-30"}, /real YYYY-MM-DD/);
  await reject({scheduled_at: "2026-10-03 09:00"}, /scheduled_at must be/);
  await reject({date: "2026-10-03", reminder_at: "2026-10-04T09:00"}, /same day/);
  await reject({scheduled_at: "2026-10-03T09:00", reminder_at: "2026-10-03T10:00"}, /at or before/);
  await reject({reminder_at: "2026-10-01T20:00"}, /already passed/);
  assert.match((await planPriority(db, "u", {operation: "create"}, req())).result, /needs a title/);
  assert.match((await planPriority(db, "u", {operation: "rename"}, req())).result, /must be create/);
});

test("propose_priority: updates and deletes resolve the exact stored priority", async () => {
  const db = fakeDb({docs: {
    [`${items("2026-09-24")}/deck`]: {title: "Finalize pitch deck", source: "manual"},
    [`${items("2026-10-02")}/standup`]: {title: "Standup", source: "calendar", sourceEventKey: "k"},
    [`${items("2026-10-03")}/a`]: {title: "Gym", source: "manual"},
    [`${items("2026-10-03")}/b`]: {title: "Gym", source: "manual"},
  }});
  assert.deepEqual((await planPriority(db, "u", {operation: "update", target_id: "2026-09-24/deck", date: "2026-10-02"}, req())).action,
      {type: "priority", operation: "update", target_title: "Finalize pitch deck", target_date: "2026-09-24", date: "2026-10-02"});
  assert.deepEqual((await planPriority(db, "u", {operation: "delete", target_id: "2026-09-24/deck"}, req())).action,
      {type: "priority", operation: "delete", target_title: "Finalize pitch deck", target_date: "2026-09-24"});
  const reject = async (input, pattern) => assert.match((await planPriority(db, "u", input, req())).result, pattern);
  await reject({operation: "delete"}, /call get_priorities first/);
  await reject({operation: "delete", target_id: "2026-09-24/nope"}, /no priority with that id/);
  await reject({operation: "delete", target_id: "../x/deck"}, /call get_priorities first/);
  await reject({operation: "update", target_id: "2026-09-24/deck"}, /nothing to change/);
  await reject({operation: "update", target_id: "2026-10-02/standup", title: "x"}, /linked to a calendar event/);
  await reject({operation: "delete", target_id: "2026-10-03/a"}, /two priorities on 2026-10-03 are called "Gym"/);
});

test("propose_calendar_change checks creates and finds existing events in SCHEDULE", () => {
  const schedule = "Fri 2026-10-02: 09:00–10:00 Investor sync; 14:00–15:00 Gym";
  const r = req({context: {schedule}});
  assert.deepEqual(planCalendar({operation: "create", title: "Run", start: "2026-10-02T18:00", end: "2026-10-02T18:45"}, r).action,
      {type: "calendar", operation: "create", title: "Run", start: "2026-10-02T18:00", end: "2026-10-02T18:45"});
  assert.match(planCalendar({operation: "create", title: "Run", start: "2026-10-02T18:00"}, r).result, /needs a title, start and end/);
  assert.match(planCalendar({operation: "create", title: "Run", start: "2026-10-02T18:00", end: "2026-10-02T17:00"}, r).result, /end must be after/);
  assert.deepEqual(planCalendar({operation: "update", target_title: "investor sync", start: "2026-10-02T11:00", end: "2026-10-02T12:00"}, r).action,
      {type: "calendar", operation: "update", target_title: "investor sync", start: "2026-10-02T11:00", end: "2026-10-02T12:00"});
  assert.match(planCalendar({operation: "delete", target_title: "Dentist"}, r).result, /no event with that title/);
  assert.match(planCalendar({operation: "delete", target_title: "Gym"}, req()).result, /calendar isn't connected/);
  assert.match(planCalendar({operation: "update", target_title: "Gym"}, r).result, /nothing to change/);
});

test("several proposals reach the app as actions, plus legacy fields; none on a crisis turn", async () => {
  const db = fakeDb({docs: {[`${items("2026-09-24")}/deck`]: {title: "Finalize pitch deck", source: "manual"}}});
  const schedule = "Fri 2026-10-02: 14:00–15:00 Gym";
  const client = fakeClient([
    {stop_reason: "tool_use", usage: {}, content: [
      toolUse("p", "propose_priority", {operation: "update", target_id: "2026-09-24/deck", date: "2026-10-02"}),
      toolUse("c", "propose_calendar_change", {operation: "update", target_title: "Gym", start: "2026-10-03T10:00", end: "2026-10-03T11:00"}),
      toolUse("bad", "propose_priority", {operation: "delete", target_id: "2026-09-24/nope"}),
    ]},
    {stop_reason: "tool_use", usage: {}, content: [toolUse("r", "reply", {message: "Here's the plan.", intent: "chitchat", crisis: false, summary: "Moved things."})]},
  ]);
  const {reply} = await runAssistant({client, db, uid: "u", now, request: req({context: {schedule}})});
  assert.deepEqual(reply.actions, [
    {type: "priority", operation: "update", target_title: "Finalize pitch deck", target_date: "2026-09-24", date: "2026-10-02"},
    {type: "calendar", operation: "update", target_title: "Gym", start: "2026-10-03T10:00", end: "2026-10-03T11:00"},
  ]);
  assert.equal(reply.intent, "priority_action");
  assert.deepEqual(reply.priority_action, {operation: "update", target_title: "Finalize pitch deck", target_date: "2026-09-24", date: "2026-10-02"});
  const results = client.requests[1].messages.at(-1).content.map((c) => c.content);
  assert.match(results[0], /^Proposed: update "Finalize pitch deck"/);
  assert.match(results[2], /^Not proposed: no priority with that id/);

  const crisis = await runAssistant({client: fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("p", "propose_priority", {operation: "create", title: "Something"}),
    toolUse("r", "reply", {message: "Are you safe right now?", intent: "chitchat", crisis: true, summary: "x"}),
  ]}]), db: fakeDb(), uid: "u", now, request: req()});
  assert.equal(crisis.reply.actions, undefined);
  assert.equal(crisis.reply.intent, "chitchat");
});

test("forgetting a fact also forgets the summary of the chat it came from", async () => {
  const db = fakeDb({
    memory: [
      {id: "investor", data: {kind: "stressor", text: "Investor meetings are a recurring stressor", conversationId: "old-chat"}},
      {id: "here", data: {kind: "helps", text: "Runs help", conversationId: "this-chat"}},
      {id: "legacy", data: {kind: "context", text: "Has a dog"}},
    ],
    conversations: [{id: "old-chat", data: {summary: "Investor meetings stress them.", updatedAt: at("2026-10-01T20:00:00Z")}}],
  });
  await runAssistant({client: fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("a", "save_memory", {action: "forget", id: "investor"}),
    toolUse("b", "save_memory", {action: "forget", id: "here"}),
    toolUse("c", "save_memory", {action: "forget", id: "legacy"}),
    toolUse("r", "reply", {message: "Done.", intent: "chitchat", crisis: false, summary: "Cleared some notes."}),
  ]}]), db, uid: "u", now, request: req({conversationId: "this-chat"})});
  assert.deepEqual(memoryWrites(db).map((w) => `${w.op} ${w.path}`), [
    "delete users/u/memory/investor",
    "delete users/u/conversations/old-chat",
    "delete users/u/memory/here",
    "delete users/u/memory/legacy",
    "merge users/u/conversations/this-chat",
  ]);
  assert.match(SYSTEM_PROMPT, /Leave out anything the user asked you to forget/);
});

test("charts use the real stored values, never the model's", async () => {
  const db = fakeDb({
    days: {"2026-09-28": {sleep: {avg: 6.3}}, "2026-09-29": {sleep: {avg: 7.04}}, "2026-09-30": {steps: {sum: 900}}, "2026-10-01": {sleep: {avg: 8}}},
    scores: {"2026-09-30": {capacity: {score: 73}}, "2026-10-01": {capacity: {score: 81}, effort: {total: 26.6}}},
  });
  assert.deepEqual(await chartBlock(db, "u", {metric: "sleep", start_date: "2026-09-28", end_date: "2026-10-01"}), {
    type: "metric", metric: "sleep", label: "Sleep", unit: "h", screen: "sleep",
    points: [{day: "2026-09-28", value: 6.3}, {day: "2026-09-29", value: 7}, {day: "2026-10-01", value: 8}], average: 7.1,
  });
  assert.deepEqual((await chartBlock(db, "u", {metric: "capacity", start_date: "2026-09-30", end_date: "2026-10-01"})).points,
      [{day: "2026-09-30", value: 73}, {day: "2026-10-01", value: 81}]);
  assert.equal(await chartBlock(db, "u", {metric: "effort", start_date: "2026-09-30", end_date: "2026-10-01"}), null, "one point isn't a chart");
  assert.equal(await chartBlock(db, "u", {metric: "wellness", start_date: "2026-09-30", end_date: "2026-10-01"}), null);
  assert.equal(await chartBlock(db, "u", {metric: "sleep", start_date: "2026-10-01", end_date: "2026-09-01"}), null);
});

test("source chips group lookups by screen", () => {
  assert.deepEqual(sourceBlocks([
    {name: "get_metrics", input: {start_date: "2026-09-18", end_date: "2026-10-01", metrics: ["sleep", "hrv", "resting_heart_rate"]}},
    {name: "get_scores", input: {start_date: "2026-09-29", end_date: "2026-10-01"}},
    {name: "get_workouts", input: {limit: 3}},
    {name: "get_priorities", input: {start_date: "2026-10-03", end_date: "2026-10-03"}},
  ]), [
    {type: "source", label: "Sleep", screen: "sleep", start: "2026-09-18", end: "2026-10-01"},
    {type: "source", label: "HRV, Resting heart rate", screen: "heart", start: "2026-09-18", end: "2026-10-01"},
    {type: "source", label: "Capacity, Effort", screen: "my_day", start: "2026-09-29", end: "2026-10-01"},
    {type: "source", label: "Physical Health", screen: "physical_health", start: "2026-09-29", end: "2026-10-01"},
  ], "at most 4 chips");
  assert.deepEqual(sourceBlocks([{name: "get_metrics", input: {start_date: "2026-10-01", end_date: "2026-10-01"}}]),
      [{type: "source", label: "Health data", screen: "metrics", start: "2026-10-01", end: "2026-10-01"}]);
  assert.deepEqual(sourceBlocks([]), []);
});

test("a full turn returns text, chart, actions and sources as blocks, plus suggestions", async () => {
  const db = fakeDb({days: {"2026-09-30": {sleep: {avg: 6}}, "2026-10-01": {sleep: {avg: 7.5}}}});
  const client = fakeClient([
    {stop_reason: "tool_use", usage: {}, content: [
      toolUse("m", "get_metrics", {start_date: "2026-09-30", end_date: "2026-10-01", metrics: ["sleep"]}),
      toolUse("bad", "get_metrics", {start_date: "nope", end_date: "2026-10-01"}),
    ]},
    {stop_reason: "tool_use", usage: {}, content: [
      toolUse("p", "propose_priority", {operation: "create", title: "Bed by 11", date: "2026-10-02"}),
      toolUse("r", "reply", {message: "Short night, then better.", intent: "chitchat", crisis: false, summary: "Sleep.",
        chart: {metric: "sleep", start_date: "2026-09-30", end_date: "2026-10-01"},
        suggestions: ["Plan my evening", " ", "What helped last time?", "Why?", "One too many"]}),
    ]},
  ]);
  const {reply} = await runAssistant({client, db, uid: "u", now, request: req()});
  assert.deepEqual(reply.blocks.map((b) => b.type), ["text", "metric", "action", "source"]);
  assert.deepEqual(reply.blocks[1].points, [{day: "2026-09-30", value: 6}, {day: "2026-10-01", value: 7.5}]);
  assert.deepEqual(reply.blocks[2].action, {type: "priority", operation: "create", title: "Bed by 11", date: "2026-10-02"});
  assert.equal(reply.blocks.filter((b) => b.type === "source").length, 1, "the failed lookup gets no chip");
  assert.deepEqual(reply.suggestions, ["Plan my evening", "What helped last time?", "Why?"]);
  assert.equal(reply.chart, undefined, "the raw chart request isn't sent on");
  assert.match(SYSTEM_PROMPT, /HOW REPLIES LOOK/);
  assert.match(SYSTEM_PROMPT, /\[Proposed changes: \.\.\.\] saying whether each was done/);
  assert.match(SYSTEM_PROMPT, /\[Asked from the "X" insight\]/);
});

test("the thread: continues within 6 hours, starts a new conversation after", async () => {
  const hour = 3600000;
  const messages = [
    {id: "m3", data: {role: "assistant", text: "Sure.", conversationId: "c-old", t: 10 * hour}},
    {id: "m2", data: {role: "user", text: "Plan my day", conversationId: "c-old", t: 10 * hour - 5000}},
    {id: "m1", data: {role: "user", text: "Older chat", conversationId: "c-older", t: 1 * hour}},
  ];
  const db = fakeDb({messages});
  assert.deepEqual(await loadThread(db, "u", req(), 12 * hour), {conversationId: "c-old",
    history: [{role: "user", text: "Plan my day"}, {role: "assistant", text: "Sure."}]});
  assert.deepEqual(await loadThread(db, "u", req(), 17 * hour), {conversationId: `c${17 * hour}`, history: []});
  assert.deepEqual(await loadThread(fakeDb(), "u", req(), 5), {conversationId: "c5", history: []});
  assert.equal((await loadThread(db, "u", req({conversationId: "legacy"}), 12 * hour)).conversationId, "legacy");
});

test("each turn saves the message and the reply to the thread, in order", async () => {
  const hour = 3600000;
  const db = fakeDb({messages: [{id: "m1", data: {role: "user", text: "Earlier", conversationId: "c-1", t: hour}}]});
  const times = [2 * hour, 2 * hour];
  const client = fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("r", "reply", {message: "Hi again.", intent: "chitchat", crisis: false, summary: "Said hi.", suggestions: ["Plan my day"]}),
  ]}]);
  const {reply} = await runAssistant({client, db, uid: "u", now, clock: () => times.shift(), request: req()});
  assert.equal(reply.conversationId, "c-1");
  assert.deepEqual(client.requests[0].messages[0], {role: "user", content: "Earlier"}, "server-loaded history");
  const thread = db.writes.filter((w) => w.path.includes("/messages/")).map((w) => w.data);
  assert.deepEqual(thread, [
    {role: "user", text: "How did I sleep?", conversationId: "c-1", t: 2 * hour, createdAt: "TS"},
    {role: "assistant", text: "Hi again.", blocks: [{type: "text", text: "Hi again."}], suggestions: ["Plan my day"],
      crisis: false, conversationId: "c-1", t: 2 * hour + 1, createdAt: "TS"},
  ]);

  const legacy = fakeDb({messages: [{id: "m1", data: {role: "user", text: "Server copy", conversationId: "c-1", t: hour}}]});
  const legacyClient = fakeClient([{stop_reason: "tool_use", usage: {}, content: [
    toolUse("r", "reply", {message: "Ok.", intent: "chitchat", crisis: false, summary: "x"})]}]);
  await runAssistant({client: legacyClient, db: legacy, uid: "u", now, clock: () => 2 * hour,
    request: req({history: [{role: "user", text: "App copy"}]})});
  assert.deepEqual(legacyClient.requests[0].messages[0], {role: "user", content: "App copy"}, "older builds still send history");
});

test("the thread tells the model what became of earlier proposals", async () => {
  const db = fakeDb({messages: [
    {id: "a", data: {role: "assistant", text: "Here's the plan.", conversationId: "c", t: 2, actionStatus: {0: "done"},
      blocks: [{type: "text", text: "Here's the plan."},
        {type: "action", action: {type: "priority", operation: "create", title: "Stretch"}},
        {type: "action", action: {type: "calendar", operation: "create", title: "Run"}}]}},
    {id: "u", data: {role: "user", text: "Plan Saturday", conversationId: "c", t: 1}},
  ]});
  const {history} = await loadThread(db, "u", req(), 3);
  assert.equal(history[1].text, "Here's the plan.\n[Proposed changes: create priority \"Stretch\": done; create calendar \"Run\": not confirmed]");
  assert.equal(history[0].text, "Plan Saturday");
});

test("a message sent from an insight card says so, to the model and in the thread", async () => {
  const request = validateAssistantRequest({message: "What does this mean?", today: "2026-10-01", now: "x", askedFrom: " Daily sleep "});
  assert.equal(request.askedFrom, "Daily sleep");
  assert.equal(validateAssistantRequest({message: "hi", today: "2026-10-01", now: "x", askedFrom: 5}).askedFrom, null);
  const db = fakeDb({messages: [
    {id: "u", data: {role: "user", text: "What does this mean?", askedFrom: "Daily sleep", conversationId: "c", t: 1}},
  ]});
  const {history} = await loadThread(db, "u", req(), 2);
  assert.equal(history[0].text, "[Asked from the \"Daily sleep\" insight] What does this mean?");
  await saveMessages(db, "u", {...request, conversationId: "c"}, {message: "ok"}, () => "ts", 5, () => 6);
  const saved = db.writes.filter((w) => w.path.includes("/messages/")).map((w) => w.data);
  assert.equal(saved[0].askedFrom, "Daily sleep");
  assert.equal(saved[1].askedFrom, undefined);
});

test("the current message carries its insight note to the model", () => {
  const request = validateAssistantRequest({...base, message: "What can I do about it?", askedFrom: "Daily sleep"});
  const last = buildMessages(request, {facts: [], summaries: []}).at(-1);
  assert.equal(last.content.at(-1).text, "[Asked from the \"Daily sleep\" insight] What can I do about it?");
});
