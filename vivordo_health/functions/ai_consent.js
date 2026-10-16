"use strict";

// Vivordo AI consent on the server. The app saves the person's choice as
// users/{uid}.aiConsent {granted, version, at} when they give or withdraw it,
// and every AI callable (assistant, aiTask, classifyPlanItems) checks it, so
// withdrawing consent stops all AI processing, not just the app's calls.

// The disclosure the consent covers (AiConsent in the app): v2 added sorting
// calendar events and priorities. A lower version asks again.
const AI_CONSENT_VERSION = 2;

/**
 * Whether an AI call may run for this consent record.
 *
 * A withdrawn or out-of-date consent always refuses. An account with no
 * record yet (app builds from before consent was saved on the server) is
 * served until `required` (app_config/ai.requireConsent) is turned on, once
 * everyone is on a build that saves it.
 * @param {object|undefined} record users/{uid}.aiConsent.
 * @param {boolean} required Whether a missing record refuses.
 * @return {boolean} True when the call may run.
 */
function aiConsentAllows(record, required) {
  if (record === undefined || record === null) return !required;
  return record.granted === true &&
    Number(record.version) >= AI_CONSENT_VERSION;
}

module.exports = {AI_CONSENT_VERSION, aiConsentAllows};
