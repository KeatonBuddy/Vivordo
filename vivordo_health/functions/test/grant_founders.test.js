"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {founderCandidates} = require("../scripts/grant_founders");

const user = (uid, creationTime) => ({uid, metadata: {creationTime}});

test("founders are accounts created before the cutoff", () => {
  const cutoff = Date.parse("2026-10-08T00:00:00Z");
  const users = [
    user("early", "Tue, 01 Sep 2026 10:00:00 GMT"),
    user("atCutoff", "Thu, 08 Oct 2026 00:00:00 GMT"),
    user("late", "Fri, 09 Oct 2026 10:00:00 GMT"),
    user("noDate", undefined),
  ];
  assert.deepEqual(
      founderCandidates(users, cutoff).map(({uid}) => uid),
      ["early"],
  );
});

test("excluded accounts are left out", () => {
  const users = [
    user("a", "Tue, 01 Sep 2026 10:00:00 GMT"),
    user("test", "Tue, 01 Sep 2026 10:00:00 GMT"),
  ];
  assert.deepEqual(
      founderCandidates(users, Date.now(), new Set(["test"]))
          .map(({uid}) => uid),
      ["a"],
  );
});
