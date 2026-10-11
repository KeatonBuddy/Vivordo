"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {validatePlanRequest, cleanAnswer, classifyPlanItems} = require("../plan_classifier");

test("requests are bounded: item counts, ids, titles", () => {
  assert.ok(validatePlanRequest({}).error, "nothing to do");
  assert.ok(validatePlanRequest({events: Array(21).fill({id: "a", title: "x"})}).error);
  assert.ok(validatePlanRequest({priorities: [{id: "a", title: "x"}, {id: "a", title: "y"}]}).error, "duplicate id");
  assert.ok(validatePlanRequest({priorities: [{id: "a", title: "  "}]}).error, "empty title");
  const ok = validatePlanRequest({
    events: [{id: "e1", title: "x".repeat(500), minutes: 90.4, attendees: 3, description: "secret notes"}],
    priorities: [{id: "p1", title: "Pay rent"}],
  });
  assert.equal(ok.events[0].title.length, 120);
  assert.equal(ok.events[0].minutes, 90);
  assert.equal(ok.events[0].description, undefined, "notes are never sent");
});

test("answers keep only asked-about ids and valid values", () => {
  const request = {events: [{id: "e1"}, {id: "e2"}], priorities: [{id: "p1"}, {id: "p2"}]};
  const answer = cleanAnswer({
    events: [
      {id: "e1", category: "collaboration"},
      {id: "e1", category: "social"}, // duplicate
      {id: "zz", category: "social"}, // not asked
      {id: "e2", category: "made-up"},
    ],
    priorities: [
      {id: "p1", effort: "light", minutes: 13},
      {id: "p2", effort: "moderate", minutes: 9000},
    ],
  }, request);
  assert.deepEqual(answer.events, [{id: "e1", category: "collaboration"}]);
  assert.deepEqual(answer.priorities, [
    {id: "p1", effort: "light", minutes: 15},
    {id: "p2", effort: "moderate", minutes: 480},
  ]);
});

test("calls Opus 5.5 at low effort with a JSON schema; titles only", async () => {
  let sent;
  const client = {messages: {create: async (body) => {
    sent = body;
    return {stop_reason: "end_turn", content: [{type: "text", text: JSON.stringify({
      events: [{id: "e1", category: "focused-work"}], priorities: [],
    })}]};
  }}};
  const request = validatePlanRequest({events: [{id: "e1", title: "Deep work", minutes: 120}]});
  const result = await classifyPlanItems(client, request);
  assert.equal(sent.model, "claude-opus-5-5");
  assert.equal(sent.output_config.effort, "low");
  assert.equal(sent.output_config.format.type, "json_schema");
  assert.deepEqual(JSON.parse(sent.messages[0].content).events[0], {id: "e1", title: "Deep work", minutes: 120, attendees: 0});
  assert.deepEqual(result.events, [{id: "e1", category: "focused-work"}]);
  // A refusal or truncated answer is treated as "no answer".
  client.messages.create = async () => ({stop_reason: "max_tokens", content: []});
  assert.deepEqual(await classifyPlanItems(client, request), {events: [], priorities: []});
});

test("a break can come back as rest", () => {
  const answer = cleanAnswer({events: [{id: "e1", category: "rest"}], priorities: []}, {events: [{id: "e1"}], priorities: []});
  assert.deepEqual(answer.events, [{id: "e1", category: "rest"}]);
});
