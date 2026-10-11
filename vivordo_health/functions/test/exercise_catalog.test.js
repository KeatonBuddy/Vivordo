"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {buildCatalogDocument} = require("../exercise_catalog");
const seed = require("../scripts/exercise_catalog_seed.json");

test("wraps entries in a versioned document", () => {
  const doc = buildCatalogDocument(
      [{n: "Barbell Row", c: "Back"}],
      4,
  );

  assert.equal(doc.version, 4);
  assert.deepEqual(doc.exercises, [{n: "Barbell Row", c: "Back"}]);
});

test("preserves entry order", () => {
  const doc = buildCatalogDocument(
      [{n: "A", c: "Chest"}, {n: "B", c: "Back"}, {n: "C", c: "Legs"}],
      1,
  );

  assert.deepEqual(doc.exercises.map((e) => e.n), ["A", "B", "C"]);
});

test("rejects an entry with no name", () => {
  assert.throws(
      () => buildCatalogDocument([{n: "  ", c: "Chest"}], 1),
      /name/,
  );
});

test("defaults a missing category to Other", () => {
  const doc = buildCatalogDocument([{n: "Sled Push"}], 1);

  assert.equal(doc.exercises[0].c, "Other");
});

test("the committed seed has 1128 uniquely named entries", () => {
  assert.equal(seed.length, 1128);
  assert.equal(new Set(seed.map((e) => e.n)).size, 1128);
});

test("the committed seed builds a document under the 1MB limit", () => {
  const doc = buildCatalogDocument(seed, 1);

  assert.equal(doc.exercises.length, 1128);
  assert.ok(
      Buffer.byteLength(JSON.stringify(doc)) < 1024 * 1024,
      "catalog document must fit in one Firestore document",
  );
});
