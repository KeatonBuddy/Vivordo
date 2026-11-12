"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {shortName} = require("../push");

test("names in notifications are one line and at most 40 characters", () => {
  assert.equal(shortName("  Rob  ", "A friend"), "Rob");
  assert.equal(shortName("a\nReporter: b", "A friend"), "a Reporter: b");
  assert.equal(shortName("x".repeat(500), "A friend").length, 40);
  assert.equal(shortName("   ", "A friend"), "A friend");
  assert.equal(shortName({toString: () => "x"}, "A friend"), "A friend");
});
