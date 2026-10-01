"use strict";

// Bounds on the pandaClaude proxy. The app still builds its prompts on the
// client, so without these any signed-in account could use the Anthropic key
// as a general-purpose Claude endpoint with unlimited size and volume.
// ponytail: client-supplied prompts; move them server-side to close the
// remaining "custom prompt within budget" gap.
const MAX_OUTPUT_TOKENS = 2000; // spike analysis asks for 1800, chat 800
const MAX_INPUT_CHARS = 48000; // largest real call is ~35k chars
const DAILY_CALL_LIMIT = 200; // a heavy chat day is well under 100 calls

/**
 * Rebuilds request blocks as plain text blocks, dropping anything else
 * (images, documents, tool blocks) a modified client could smuggle in.
 *
 * @param {*} value A string or an array of {type, text, cache_control}.
 * @return {Array<Object>|null} Sanitised blocks, or null when invalid.
 */
function textBlocks(value) {
  const raw = typeof value === "string" ? [{type: "text", text: value}] : value;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 8) return null;
  const blocks = [];
  for (const block of raw) {
    if (!block || block.type !== "text" || typeof block.text !== "string") {
      return null;
    }
    blocks.push(block.cache_control ?
      {type: "text", text: block.text, cache_control: {type: "ephemeral"}} :
      {type: "text", text: block.text});
  }
  return blocks;
}

/**
 * Validates a pandaClaude request.
 *
 * @param {Object} data The callable's request.data.
 * @return {{system: Array, user: Array, maxTokens: number}|{error: string}}
 */
function validatePandaRequest(data) {
  const system = textBlocks(data?.system);
  const user = textBlocks(data?.user);
  if (!system || !user) return {error: "system and user must be text."};
  const chars = [...system, ...user]
      .reduce((sum, block) => sum + block.text.length, 0);
  if (chars > MAX_INPUT_CHARS) return {error: "Request is too large."};
  const requested = Number(data?.maxTokens);
  const maxTokens = Number.isFinite(requested) && requested > 0 ?
    Math.min(Math.floor(requested), MAX_OUTPUT_TOKENS) : 300;
  return {system, user, maxTokens};
}

/**
 * Next daily usage record, or null when today's limit is spent.
 *
 * @param {Object|undefined} current Stored {day, count}.
 * @param {string} day Today's UTC day key (YYYY-MM-DD).
 * @param {number} limit Calls allowed per day.
 * @return {{day: string, count: number}|null}
 */
function nextUsage(current, day, limit = DAILY_CALL_LIMIT) {
  const count = current?.day === day ? Number(current.count) || 0 : 0;
  return count >= limit ? null : {day, count: count + 1};
}

module.exports = {
  validatePandaRequest,
  nextUsage,
  MAX_OUTPUT_TOKENS,
  MAX_INPUT_CHARS,
  DAILY_CALL_LIMIT,
};
