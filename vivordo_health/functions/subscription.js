"use strict";

// Vivordo Premium status, kept in subscriptions/{uid} (client-readable,
// server-written only). RevenueCat is the source of truth: its webhook and
// the app's refresh call both fetch the subscriber from RevenueCat's API and
// store what it says, so every event type (renewal, cancellation, billing
// issue, refund, transfer) is handled the same way.

// The entitlement's identifier in RevenueCat (Product catalog →
// Entitlements), which can't be renamed there.
const ENTITLEMENT = "vivordo_premium";
const REVENUECAT_API = "https://api.revenuecat.com/v1/subscribers/";

/**
 * The stored status for a RevenueCat subscriber: whether Premium is active
 * now, and the details Settings shows.
 * @param {object} subscriber RevenueCat's `subscriber` object.
 * @param {number} now Current time in ms.
 * @return {object} Fields for subscriptions/{uid}.
 */
function subscriptionFromSubscriber(subscriber, now) {
  const entitlement = subscriber?.entitlements?.[ENTITLEMENT];
  const productId = entitlement?.product_identifier ?? null;
  const product = productId ? subscriber?.subscriptions?.[productId] : null;
  // A null expiry is a lifetime grant (for example, a promotional one).
  const expiresMs = entitlement?.expires_date ?
    Date.parse(entitlement.expires_date) : null;
  const active = Boolean(entitlement) &&
    (expiresMs === null || expiresMs > now);
  return {
    active,
    productId,
    period: product?.period_type ?? null, // trial, intro or normal
    expiresAt: expiresMs === null ? null : new Date(expiresMs),
    willRenew: Boolean(product) && !product.unsubscribe_detected_at &&
      !product.billing_issues_detected_at,
    billingIssue: Boolean(product?.billing_issues_detected_at),
    sandbox: Boolean(product?.is_sandbox),
    store: product?.store ?? null,
  };
}

/**
 * Whether stored status still grants Premium at [now].
 * @param {object|undefined} status A subscriptions/{uid} document.
 * @param {number} now Current time in ms.
 * @return {boolean} True while active and unexpired.
 */
function hasPremium(status, now) {
  if (!status?.active) return false;
  const expires = status.expiresAt?.toMillis?.() ?? null;
  return expires === null || expires > now;
}

/**
 * The account ids a RevenueCat webhook event concerns: the user it's about,
 * and for a transfer (a restore on another account) both sides.
 * @param {object} event The webhook body's `event`.
 * @return {string[]} Distinct ids, anonymous RevenueCat ids left out.
 */
function webhookUserIds(event) {
  const ids = [
    event?.app_user_id,
    ...(event?.transferred_from ?? []),
    ...(event?.transferred_to ?? []),
  ];
  return [...new Set(ids.filter((id) =>
    typeof id === "string" && id && !id.startsWith("$RCAnonymousID")))];
}

/**
 * Fetches a subscriber from RevenueCat and stores their status.
 * @param {object} db Firestore.
 * @param {string} uid Firebase uid (the RevenueCat app user id).
 * @param {string} apiKey RevenueCat secret API key.
 * @param {Function} fetchImpl fetch, injectable for tests.
 * @return {Promise<object>} The stored status.
 */
async function refreshFromRevenueCat(db, uid, apiKey, fetchImpl = fetch) {
  const response = await fetchImpl(REVENUECAT_API + encodeURIComponent(uid), {
    headers: {Authorization: `Bearer ${apiKey}`},
  });
  if (!response.ok) {
    throw new Error(`RevenueCat ${response.status} for ${uid}`);
  }
  const {subscriber} = await response.json();
  const status = subscriptionFromSubscriber(subscriber, Date.now());
  await db.collection("subscriptions").doc(uid).set({
    ...status,
    updatedAt: new Date(),
  });
  return status;
}

module.exports = {
  ENTITLEMENT,
  subscriptionFromSubscriber,
  hasPremium,
  webhookUserIds,
  refreshFromRevenueCat,
};
