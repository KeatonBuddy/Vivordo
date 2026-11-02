"use strict";

// The units the app shows (Settings → Units), sent with Vivordo AI
// requests so replies use them. Stored data keeps its own units: lift
// weights as weightLbs (pounds), distances as distanceKm, body weight in kg.

const ALLOWED = {
  bodyWeight: ["kg", "lb"],
  liftWeight: ["kg", "lb"],
  distance: ["km", "mi"],
  height: ["cm", "ftIn"],
};

const WORDS = {kg: "kg", lb: "lb", km: "km", mi: "miles", cm: "cm",
  ftIn: "feet and inches"};

/**
 * The known measures in [value], unknown keys and values dropped.
 * @param {*} value The request's units.
 * @return {Object|null} e.g. {bodyWeight: "kg", distance: "mi"}, or null.
 */
function cleanUnits(value) {
  if (!value || typeof value !== "object") return null;
  const units = {};
  for (const [key, allowed] of Object.entries(ALLOWED)) {
    if (allowed.includes(value[key])) units[key] = value[key];
  }
  return Object.keys(units).length ? units : null;
}

/**
 * A system-prompt line telling the model the user's units.
 * @param {*} value The request's units.
 * @return {string|null} The instruction, or null with no known units.
 */
function unitsInstruction(value) {
  const units = cleanUnits(value);
  if (!units) return null;
  const parts = [
    units.bodyWeight && `body weight in ${WORDS[units.bodyWeight]}`,
    units.liftWeight && `lifting weights in ${WORDS[units.liftWeight]}`,
    units.distance && `distances in ${WORDS[units.distance]}`,
    units.height && `height in ${WORDS[units.height]}`,
  ].filter(Boolean);
  return `The user's units: ${parts.join(", ")}. Always reply in these ` +
    "units. Numbers from your data tools are already in them. Raw fields " +
    "keep their stored units (weightLbs is pounds, distanceKm is " +
    "kilometres, body weight is kg): convert those before you quote them, " +
    "rounding lifts to the nearest 0.5 kg or 1 lb.";
}

const KG_PER_LB = 0.45359237;
const KM_PER_MILE = 1.609344;

/**
 * Converters from stored values (lifts in lb, distance in km, body weight
 * in kg) to the user's units, with their labels. Data tools write numbers
 * already converted: the model copies a labelled number over any
 * instruction. No units (older builds) keeps the stored units.
 * @param {*} value The request's units.
 * @return {Object} {lift, liftLabel, distance, distanceLabel, bodyWeight,
 *   bodyWeightLabel}
 */
function unitConverter(value) {
  const units = cleanUnits(value) ?? {};
  const kgLifts = units.liftWeight === "kg";
  const miles = units.distance === "mi";
  const lbBody = units.bodyWeight === "lb";
  return {
    lift: (lbs) => kgLifts ? lbs * KG_PER_LB : lbs,
    liftLabel: kgLifts ? "kg" : "lb",
    distance: (km) => miles ? km / KM_PER_MILE : km,
    distanceLabel: miles ? "mi" : "km",
    bodyWeight: (kg) => lbBody ? kg / KG_PER_LB : kg,
    bodyWeightLabel: lbBody ? "lb" : "kg",
  };
}

module.exports = {cleanUnits, unitsInstruction, unitConverter};
