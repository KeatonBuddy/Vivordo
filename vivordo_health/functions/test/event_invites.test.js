const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  validatedInviteInput, responseUpdate, removalUpdate, responseMessage,
  changeAudience, eventChanged,
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
    recipientNames: {b: "bo", c: "cy"},
  };
  assert.deepEqual(removalUpdate(invite, "b"), {
    recipientUids: ["c"], responses: {c: "pending"},
    recipientNames: {c: "cy"},
  });
  assert.equal(removalUpdate({...invite, recipientUids: ["b"]}, "b").status,
      "cancelled");
  assert.deepEqual(removalUpdate(invite, "a"), {status: "cancelled"});
});

test("the sender hears about every answer, and a change of mind", () => {
  assert.equal(responseMessage("bo", "Run club", "pending", true),
      "bo accepted Run club");
  assert.equal(responseMessage("bo", "Run club", "pending", false),
      "bo declined Run club");
  assert.equal(responseMessage("bo", "Run club", "accepted", false),
      "bo can no longer make Run club");
  assert.equal(responseMessage("bo", "Run club", "declined", true),
      "bo can attend Run club after all");
});

test("answers stop once the event has ended", () => {
  const invite = {
    recipientUids: ["b"], responses: {b: "pending"}, status: "active",
    end: now - hour,
  };
  assert.throws(() => responseUpdate(invite, "b", true, now), /ended/);
  assert.deepEqual(responseUpdate({...invite, end: now + hour}, "b", true, now),
      {"responses.b": "accepted"});
});

test("changes reach everyone still invited except those who declined", () => {
  assert.deepEqual(changeAudience({
    recipientUids: ["a", "b", "c"],
    responses: {a: "accepted", b: "pending", c: "declined"},
  }), ["a", "b"]);
});

test("only edits friends can see count as a change", () => {
  const invite = {title: "Run", start: now, end: now + hour, allDay: false};
  const same = {title: "Run", start: now, end: now + hour, allDay: false};
  assert.equal(eventChanged(invite, same), false);
  assert.equal(eventChanged(invite, {...same, end: now + 2 * hour}), true);
  assert.equal(eventChanged(invite, {...same, title: "Run club"}), true);
  const stamped = {
    ...invite,
    start: {toMillis: () => now},
    end: {toMillis: () => now + hour},
  };
  assert.equal(eventChanged(stamped, same), false);
});

test("undo takes a decline back to waiting, and nothing else", () => {
  const invite = {
    recipientUids: ["b"], responses: {b: "declined"}, status: "active",
    end: now + hour,
  };
  assert.deepEqual(responseUpdate(invite, "b", null, now),
      {"responses.b": "pending"});
  assert.equal(responseUpdate({...invite, responses: {b: "accepted"}},
      "b", null, now), null);
  assert.equal(responseUpdate({...invite, responses: {b: "pending"}},
      "b", null, now), null);
});
