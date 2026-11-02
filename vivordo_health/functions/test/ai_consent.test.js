"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {aiConsentAllows, AI_CONSENT_VERSION} = require("../ai_consent");

test("withdrawn or out-of-date consent always refuses", () => {
  for (const required of [false, true]) {
    assert.equal(
        aiConsentAllows({granted: false, version: 2}, required), false);
    assert.equal(aiConsentAllows({granted: true, version: 1}, required), false);
    assert.equal(aiConsentAllows({granted: true}, required), false);
  }
});

test("current consent allows", () => {
  for (const required of [false, true]) {
    assert.equal(aiConsentAllows(
        {granted: true, version: AI_CONSENT_VERSION}, required), true);
  }
});

test("no record yet is served only until consent is required", () => {
  assert.equal(aiConsentAllows(undefined, false), true);
  assert.equal(aiConsentAllows(undefined, true), false);
  assert.equal(aiConsentAllows(null, true), false);
});
