"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {cleanUnits, unitsInstruction, unitConverter} = require("../units");

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
  assert.match(text, /already in them/);
  assert.match(text, /weightLbs is pounds/);
  assert.equal(unitsInstruction(undefined), null);
});

test("the converter turns stored values into the user's units", () => {
  const to = unitConverter(
      {liftWeight: "kg", distance: "mi", bodyWeight: "lb"});
  assert.equal(to.lift(185).toFixed(1), "83.9");
  assert.equal(to.liftLabel, "kg");
  assert.equal(to.distance(6.1).toFixed(1), "3.8");
  assert.equal(to.distanceLabel, "mi");
  assert.equal(to.bodyWeight(78).toFixed(0), "172");
  assert.equal(to.bodyWeightLabel, "lb");
  // No units (older builds): stored units unchanged.
  const stored = unitConverter(undefined);
  assert.equal(stored.lift(185), 185);
  assert.equal(stored.distance(6.1), 6.1);
  assert.equal(stored.bodyWeight(78), 78);
  assert.deepEqual(
      [stored.liftLabel, stored.distanceLabel, stored.bodyWeightLabel],
      ["lb", "km", "kg"]);
});
