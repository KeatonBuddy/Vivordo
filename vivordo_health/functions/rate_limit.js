"use strict";

// Per-account daily budgets for things that send pushes or email or cost a
// long run. Counters live in rate_limits/{uid}_{kind}, which has no client
// rule, so only the Admin SDK can read or reset them (as with ai_usage).

const {HttpsError} = require("firebase-functions/v2/https");
const {nextUsage} = require("./ai_limits");

// Calls a day, set well above real use.
const LIMITS = {
  social: 100, // invite and challenge callables, which push to friends
  friend_requests: 30, // friend-request pushes
  reports: 10, // abuse-report emails to support
  history: 6, // rebuildHistory runs (up to 9 minutes each)
};

/**
 * Spends one of today's [kind] budget for an account.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid Account ID.
 * @param {string} kind A key of LIMITS.
 * @return {Promise<boolean>} False when today's budget is spent.
 */
async function spend(db, uid, kind) {
  const reference = db.collection("rate_limits").doc(`${uid}_${kind}`);
  const today = new Date().toISOString().slice(0, 10);
  return db.runTransaction(async (transaction) => {
    const next = nextUsage(
        (await transaction.get(reference)).data(), today, LIMITS[kind]);
    if (next) transaction.set(reference, next);
    return next !== null;
  });
}

/**
 * The same for a callable: throws once today's budget is spent.
 * @param {object} db Admin Firestore instance.
 * @param {string} uid The caller.
 * @param {string} kind A key of LIMITS.
 */
async function requireBudget(db, uid, kind) {
  if (!(await spend(db, uid, kind))) {
    throw new HttpsError(
        "resource-exhausted", "Too many requests today. Try again tomorrow.");
  }
}

module.exports = {LIMITS, spend, requireBudget};
