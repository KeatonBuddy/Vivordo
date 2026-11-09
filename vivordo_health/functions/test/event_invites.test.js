const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  validatedInviteInput, responseUpdate, removalUpdate,
} = require("../event_invites");

const now = Date.UTC(2026, 10, 9, 12);
const hour = 60 * 60 * 1000;
const valid = {
  title: " Run club ", start: now + hour, end: now + 2 * hour,
  recipientUids: ["b", "b", "a", " c ", 4], senderEventId: "evt1",
};

test("invite input trims, dedupes and drops the sender", () => {
  const input = validatedInviteInput(valid, "a", now);
  assert.equal(input.title, "Run club");
  assert.deepEqual(input.recipientUids, ["b", "c"]);
  assert.equal(input.allDay, false);
  assert.equal(input.senderEventId, "evt1");
});

test("invite input rejects bad times, titles and empty lists", () => {
  for (const data of [
    {...valid, end: valid.start},
    {...valid, start: now - 3 * hour, end: now - hour},
    {...valid, end: valid.start + 8 * 24 * hour},
    {...valid, title: "  "},
    {...valid, recipientUids: ["a"]},
    {...valid, recipientUids: Array.from({length: 21}, (_, i) => `u${i}`)},
  ]) {
    assert.throws(() => validatedInviteInput(data, "a", now));
  }
});

test("responses only come from recipients of active invites", () => {
  const invite = {
    fromUid: "a", recipientUids: ["b"], responses: {b: "pending"},
    status: "active",
  };
  assert.deepEqual(responseUpdate(invite, "b", true),
      {"responses.b": "accepted"});
  assert.equal(responseUpdate({...invite, responses: {b: "accepted"}},
      "b", true), null);
  assert.throws(() => responseUpdate(invite, "a", true));
  assert.throws(() => responseUpdate({...invite, status: "cancelled"},
      "b", false));
});

test("removing people keeps the rest and cancels when nobody is left", () => {
  const invite = {
    fromUid: "a", recipientUids: ["b", "c"],
    responses: {b: "accepted", c: "pending"},
  };
  assert.deepEqual(removalUpdate(invite, "b"),
      {recipientUids: ["c"], responses: {c: "pending"}});
  assert.equal(removalUpdate({...invite, recipientUids: ["b"]}, "b").status,
      "cancelled");
  assert.deepEqual(removalUpdate(invite, "a"), {status: "cancelled"});
});
