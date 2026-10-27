"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {cleanUnits, unitsInstruction} = require("../units");

test("only known measures and values are kept", () => {
  assert.deepEqual(
      cleanUnits({bodyWeight: "kg", distance: "furlong", x: "lb"}),
      {bodyWeight: "kg"});
  assert.equal(cleanUnits(null), null);
  assert.equal(cleanUnits({distance: "parsec"}), null);
});

test("the instruction names the user's units and how data is stored", () => {
  const text = unitsInstruction({bodyWeight: "kg", liftWeight: "lb",
    distance: "mi", height: "ftIn"});
  assert.match(text, /body weight in kg/);
  assert.match(text, /lifting weights in lb/);
  assert.match(text, /distances in miles/);
  assert.match(text, /height in feet and inches/);
  assert.match(text, /weightLbs \(pounds\)/);
  assert.equal(unitsInstruction(undefined), null);
});
