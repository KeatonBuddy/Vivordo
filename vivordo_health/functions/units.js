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
    "units. Workout data stores lifting weights as weightLbs (pounds) and " +
    "distances in km, and body weight is stored in kg: convert before you " +
    "quote them, rounding lifts to the nearest 0.5 kg or 1 lb.";
}

module.exports = {cleanUnits, unitsInstruction};
