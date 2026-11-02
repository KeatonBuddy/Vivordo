"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  subscriptionFromSubscriber,
  hasPremium,
  webhookUserIds,
  refreshFromRevenueCat,
  isStaff,
  grantStaffAccess,
} = require("../subscription");

const NOW = Date.parse("2026-11-01T12:00:00Z");
const subscriber = (expires, extra = {}) => ({
  entitlements: {vivordo_premium: {
    expires_date: expires,
    product_identifier: "vivordo_premium_yearly",
  }},
  subscriptions: {vivordo_premium_yearly: {
    expires_date: expires,
    period_type: "trial",
    store: "app_store",
    is_sandbox: true,
    unsubscribe_detected_at: null,
    billing_issues_detected_at: null,
    ...extra,
  }},
});

test("an unexpired premium entitlement is active", () => {
  const status = subscriptionFromSubscriber(
      subscriber("2026-11-13T12:00:00Z"), NOW);
  assert.equal(status.active, true);
  assert.equal(status.productId, "vivordo_premium_yearly");
  assert.equal(status.period, "trial");
  assert.equal(status.willRenew, true);
  assert.equal(status.sandbox, true);
  assert.deepEqual(status.expiresAt, new Date("2026-11-13T12:00:00Z"));
});

test("expired, cancelled and missing entitlements", () => {
  assert.equal(subscriptionFromSubscriber(
      subscriber("2026-10-31T12:00:00Z"), NOW).active, false);
  const cancelled = subscriptionFromSubscriber(subscriber(
      "2026-11-13T12:00:00Z",
      {unsubscribe_detected_at: "2026-11-02T00:00:00Z"}), NOW);
  // Cancelling keeps access until the period ends; it just won't renew.
  assert.equal(cancelled.active, true);
  assert.equal(cancelled.willRenew, false);
  assert.equal(subscriptionFromSubscriber({}, NOW).active, false);
  assert.equal(subscriptionFromSubscriber(undefined, NOW).active, false);
});

test("a lifetime grant has no expiry and stays active", () => {
  const status = subscriptionFromSubscriber(subscriber(null), NOW);
  assert.equal(status.active, true);
  assert.equal(status.expiresAt, null);
  assert.equal(hasPremium({active: true, expiresAt: null}, NOW), true);
});

test("stored status grants Premium only until it expires", () => {
  const at = (iso) => ({toMillis: () => Date.parse(iso)});
  assert.equal(
      hasPremium({active: true, expiresAt: at("2026-11-02T00:00:00Z")}, NOW),
      true);
  assert.equal(
      hasPremium({active: true, expiresAt: at("2026-10-31T00:00:00Z")}, NOW),
      false);
  assert.equal(hasPremium({active: false}, NOW), false);
  assert.equal(hasPremium(undefined, NOW), false);
});

test("webhook events name every account they touch", () => {
  assert.deepEqual(webhookUserIds({app_user_id: "alice"}), ["alice"]);
  assert.deepEqual(webhookUserIds({
    type: "TRANSFER",
    app_user_id: "bob",
    transferred_from: ["alice", "$RCAnonymousID:abc"],
    transferred_to: ["bob"],
  }), ["bob", "alice"]);
  assert.deepEqual(webhookUserIds(undefined), []);
});

test("refreshing stores what RevenueCat says", async () => {
  const writes = [];
  const db = {collection: (name) => ({doc: (id) => ({
    set: async (data) => writes.push({name, id, data}),
  })})};
  let asked;
  const fetchImpl = async (url, options) => {
    asked = {url, auth: options.headers.Authorization};
    return {ok: true, json: async () => ({
      subscriber: subscriber("2099-01-01T00:00:00Z"),
    })};
  };
  const status = await refreshFromRevenueCat(db, "uid/1", "sk_test", fetchImpl);
  assert.equal(status.active, true);
  assert.equal(asked.url,
      "https://api.revenuecat.com/v1/subscribers/uid%2F1");
  assert.equal(asked.auth, "Bearer sk_test");
  assert.equal(writes[0].name, "subscriptions");
  assert.equal(writes[0].id, "uid/1");
  assert.equal(writes[0].data.active, true);

  await assert.rejects(refreshFromRevenueCat(db, "x", "k",
      async () => ({ok: false, status: 500})), /RevenueCat 500/);
});

test("staff are verified emails on the list, any case", () => {
  const list = ["Alex@Example.com", " sam@example.com "];
  assert.equal(isStaff({email: "alex@example.com", email_verified: true},
      list), true);
  assert.equal(isStaff({email: "SAM@example.com", email_verified: true},
      list), true);
  // Unverified, not on the list, no email, no list.
  assert.equal(isStaff({email: "alex@example.com", email_verified: false},
      list), false);
  assert.equal(isStaff({email: "kim@example.com", email_verified: true},
      list), false);
  assert.equal(isStaff({email_verified: true}, list), false);
  assert.equal(isStaff({email: "alex@example.com", email_verified: true},
      undefined), false);
  assert.equal(isStaff(undefined, list), false);
});

test("staff access is a promotional grant in RevenueCat", async () => {
  const writes = [];
  const db = {collection: (name) => ({doc: (id) => ({
    set: async (data) => writes.push({name, id, data}),
  })})};
  let asked;
  const fetchImpl = async (url, options) => {
    asked = {url, ...options};
    return {ok: true, json: async () => ({
      subscriber: {entitlements: {vivordo_premium: {
        expires_date: "2100-01-01T00:00:00Z",
        product_identifier: "rc_promo_vivordo_premium_custom",
      }}},
    })};
  };
  const status = await grantStaffAccess(db, "uid1", "sk_test", fetchImpl);
  assert.equal(asked.url, "https://api.revenuecat.com/v1/subscribers/uid1/" +
      "entitlements/vivordo_premium/promotional");
  assert.equal(asked.method, "POST");
  assert.equal(asked.headers.Authorization, "Bearer sk_test");
  assert.deepEqual(JSON.parse(asked.body),
      {end_time_ms: Date.parse("2100-01-01T00:00:00Z")});
  assert.equal(status.active, true);
  assert.equal(writes[0].id, "uid1");
  assert.equal(writes[0].data.active, true);

  await assert.rejects(grantStaffAccess(db, "x", "k",
      async () => ({ok: false, status: 403})), /RevenueCat 403/);
});
