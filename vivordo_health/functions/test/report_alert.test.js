"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {reportEmail} = require("../report_alert");

test("report emails say what, why, who and where", () => {
  const {subject, text} = reportEmail("r1", {
    type: "challenge_comment",
    reporterUid: "bob",
    challengeId: "c1",
    commentId: "k1",
    authorUid: "alice",
    reason: "inappropriate_content",
    details: " rude ",
  });
  assert.equal(
      subject,
      "Vivordo report: Challenge comment · inappropriate content",
  );
  assert.match(text, /Details: rude\n/);
  assert.match(text, /Reported user: alice/);
  assert.match(text, /Challenge: challenges\/c1/);
  assert.match(text, /reports~2Fr1$/);
});

test("older feed-post reports have no type", () => {
  const {subject, text} = reportEmail("r2", {
    reporterUid: "bob",
    postOwnerUid: "alice",
    postId: "p1",
    reason: "spam",
    details: "",
  });
  assert.equal(subject, "Vivordo report: Feed post · spam");
  assert.match(text, /Details: \(none\)/);
  assert.match(text, /Post: users\/alice\/circle_activity\/p1/);
});
