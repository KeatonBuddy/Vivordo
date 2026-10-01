"use strict";
/* eslint-disable max-len, require-jsdoc */
const test = require("node:test");
const assert = require("node:assert/strict");
const {validatePandaRequest, nextUsage, MAX_OUTPUT_TOKENS, MAX_INPUT_CHARS} = require("../panda_limits");

const block = (text, cache) => cache ? {type: "text", text, cache_control: {type: "ephemeral"}} : {type: "text", text};

test("accepts the app's real request shape and keeps cache markers", () => {
  const result = validatePandaRequest({system: [block("sys", true)], user: [block("hi")], maxTokens: 800});
  assert.deepEqual(result, {system: [block("sys", true)], user: [block("hi")], maxTokens: 800});
});

test("caps output tokens and defaults a missing cap", () => {
  assert.equal(validatePandaRequest({system: "s", user: "u", maxTokens: 64000}).maxTokens, MAX_OUTPUT_TOKENS);
  assert.equal(validatePandaRequest({system: "s", user: "u"}).maxTokens, 300);
  assert.equal(validatePandaRequest({system: "s", user: "u", maxTokens: -5}).maxTokens, 300);
});

test("rejects oversized input", () => {
  const big = "x".repeat(MAX_INPUT_CHARS);
  assert.ok(validatePandaRequest({system: "s", user: big}).error);
  assert.ok(!validatePandaRequest({system: "", user: big}).error);
});

test("rejects non-text blocks and strips unknown fields", () => {
  const image = {type: "image", source: {type: "base64", media_type: "image/png", data: "AAAA"}};
  assert.ok(validatePandaRequest({system: "s", user: [image]}).error);
  assert.ok(validatePandaRequest({system: "s"}).error);
  assert.ok(validatePandaRequest({system: [], user: "u"}).error);
  const result = validatePandaRequest({system: [{type: "text", text: "s", citations: [1], cache_control: {type: "ephemeral", ttl: "1h"}}], user: "u"});
  assert.deepEqual(result.system, [block("s", true)]);
});

test("daily usage resets each day and stops at the limit", () => {
  assert.deepEqual(nextUsage(undefined, "2026-10-01", 2), {day: "2026-10-01", count: 1});
  assert.deepEqual(nextUsage({day: "2026-10-01", count: 1}, "2026-10-01", 2), {day: "2026-10-01", count: 2});
  assert.equal(nextUsage({day: "2026-10-01", count: 2}, "2026-10-01", 2), null);
  assert.deepEqual(nextUsage({day: "2026-09-30", count: 2}, "2026-10-01", 2), {day: "2026-10-01", count: 1});
});
