"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {buildTask, runTask, CHECKIN_SYSTEM, SUMMARY_SYSTEM} = require("../ai_tasks");

function fakeClient(response) {
  const calls = [];
  const create = (kind) => async (params) => {
    calls.push({kind, params});
    return response;
  };
  return {calls, messages: {create: create("messages")}, beta: {messages: {create: create("beta")}}};
}

test("unknown tasks and bad input are rejected", () => {
  assert.match(buildTask({task: "anything"}).error, /task must be one of/);
  assert.match(buildTask({}).error, /task must be one of/);
  assert.ok(buildTask({task: "checkin_questions", input: {}}).error);
  assert.ok(buildTask({task: "checkin_questions", input: {compact: {spike_candidates: Array(6).fill({})}}}).error);
  assert.ok(buildTask({task: "checkin_questions", input: {compact: {spike_candidates: [], pad: "x".repeat(30000)}}}).error);
  assert.ok(buildTask({task: "session_summary", input: {conversation: []}}).error);
  assert.ok(buildTask({task: "workout_insight", input: {context: ""}}).error);
  assert.ok(buildTask({task: "workout_insight", input: {context: "x".repeat(20001)}}).error);
});

test("check-in questions: server prompt, app data, Haiku", () => {
  const call = buildTask({task: "checkin_questions", input: {compact: {spike_candidates: [{day: "Tue, Sep 29"}], _variability_seed: 7, user_context: ""}}});
  assert.equal(call.model, "claude-haiku-4-5");
  assert.equal(call.maxTokens, 1800);
  assert.equal(call.system, CHECKIN_SYSTEM);
  assert.match(call.system, /You are Vivordo Stress Labeling Assistant/);
  assert.match(call.user, /_variability_seed = 7\)/);
  assert.match(call.user, /DATA: \{"spike_candidates":\[\{"day":"Tue, Sep 29"\}\]/);
  assert.match(buildTask({task: "checkin_questions", input: {compact: {spike_candidates: [], _variability_seed: "x"}}}).user, /_variability_seed = 0\)/);
});

test("session summary: last 8 turns, capped slots and answers", () => {
  const conversation = Array.from({length: 12}, (_, i) => ({role: i % 2 ? "assistant" : "user", text: `turn ${i}`}));
  conversation.push({role: "user", text: "  "});
  const call = buildTask({task: "session_summary", input: {
    conversation, slots: {stressor: "deadlines", empty: "", bad: 5}, labeledAnswers: {},
  }});
  assert.equal(call.model, "claude-haiku-4-5");
  assert.equal(call.system, SUMMARY_SYSTEM);
  assert.equal(call.user, "EXTRACTED SLOTS: {\"stressor\":\"deadlines\"}\n\nLABELED ANSWERS: none\n\nCONVERSATION:\n" +
    ["User: turn 4", "Assistant: turn 5", "User: turn 6", "Assistant: turn 7", "User: turn 8", "Assistant: turn 9", "User: turn 10", "Assistant: turn 11"].join("\n") +
    "\n\nWrite the continuity note now.");
});

test("workout insight: original coach prompt on Sonnet with fallback", async () => {
  const call = buildTask({task: "workout_insight", input: {context: "{\"workoutId\":\"w1\"}"}});
  assert.match(call.system, /Act as Vivordo’s supportive, practical fitness coach/);
  assert.match(call.system, /at most 80 words\. Return plain text\.$/);
  const client = fakeClient({stop_reason: "end_turn", usage: {}, content: [{type: "thinking", thinking: ""}, {type: "text", text: " Nice session. "}]});
  assert.equal((await runTask(client, call)).text, "Nice session.");
  assert.equal(client.calls[0].kind, "beta");
  assert.equal(client.calls[0].params.model, "claude-sonnet-5-5");
  assert.equal(client.calls[0].params.fallbacks, "default");
  assert.deepEqual(client.calls[0].params.output_config, {effort: "low"});
});

test("Haiku tasks use the plain endpoint; a refusal returns empty text", async () => {
  const call = buildTask({task: "session_summary", input: {conversation: [{role: "user", text: "hi"}]}});
  const client = fakeClient({stop_reason: "refusal", usage: {}, content: []});
  assert.equal((await runTask(client, call)).text, "");
  assert.equal(client.calls[0].kind, "messages");
  assert.equal(client.calls[0].params.fallbacks, undefined);
  assert.equal(client.calls[0].params.output_config, undefined);
  assert.deepEqual(client.calls[0].params.messages, [{role: "user", content: call.user}]);
});
