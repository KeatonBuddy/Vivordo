"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {googleHealthVitals, whoopVitals} = require("../wearable_vitals");

const date = {year: 2026, month: 10, day: 1};

test("Google vitals preserve units and separate RMSSD from SDNN", () => {
  const days = googleHealthVitals({
    "daily-resting-heart-rate": [{dailyRestingHeartRate: {
      date, beatsPerMinute: "57",
    }}],
    "daily-heart-rate-variability": [{dailyHeartRateVariability: {
      date, averageHeartRateVariabilityMilliseconds: 42.5,
      deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds: 65,
    }}],
    "daily-oxygen-saturation": [{dailyOxygenSaturation: {
      date, averagePercentage: 97.4, lowerBoundPercentage: 94,
    }}],
    "daily-respiratory-rate": [{dailyRespiratoryRate: {
      date, breathsPerMinute: 14.2,
    }}],
  });
  assert.deepEqual(days["2026-10-01"], {
    resting_heart_rate: {avg: 57, unit: "bpm"},
    hrv_rmssd: {avg: 42.5, unit: "ms", method: "rmssd"},
    blood_oxygen: {avg: 97.4, unit: "%"},
    respiratory_rate: {avg: 14.2, unit: "brpm"},
  });
  assert.equal(days["2026-10-01"].hrv, undefined);
});

test("missing or invalid vitals never become zero", () => {
  for (const value of [undefined, null, "", " ", false, {}, -1, 0, NaN,
    Infinity, "invalid"]) {
    assert.deepEqual(googleHealthVitals({
      "daily-resting-heart-rate": [{dailyRestingHeartRate: {
        date, beatsPerMinute: value,
      }}],
      "daily-heart-rate-variability": [{dailyHeartRateVariability: {
        date, averageHeartRateVariabilityMilliseconds: value,
      }}],
    }), {});
  }
  assert.deepEqual(googleHealthVitals({
    "daily-oxygen-saturation": [{dailyOxygenSaturation: {
      date, averagePercentage: 101,
    }}],
    "daily-respiratory-rate": [{dailyRespiratoryRate: {
      date: {year: 2026, month: 2, day: 30}, breathsPerMinute: 15,
    }}],
  }), {});
  assert.deepEqual(googleHealthVitals({}), {});
});

const sleep = {
  id: "sleep-1", start: "2026-09-30T17:00:00Z",
  end: "2026-10-01T01:00:00Z", timezone_offset: "-06:00",
  score_state: "SCORED", nap: false, score: {respiratory_rate: 14.1},
};
const recovery = {
  sleep_id: "sleep-1", updated_at: "2026-10-02T12:00:00Z",
  score_state: "SCORED",
  score: {
    resting_heart_rate: 58, hrv_rmssd_milli: 44.3, spo2_percentage: 96.7,
    recovery_score: 83, skin_temp_celsius: 33.7,
  },
};

test("WHOOP uses local wake day and excludes proprietary scores", () => {
  assert.deepEqual(whoopVitals([sleep], [recovery]), {
    "2026-09-30": {
      respiratory_rate: {avg: 14.1, unit: "brpm"},
      resting_heart_rate: {avg: 58, unit: "bpm"},
      hrv_rmssd: {avg: 44.3, unit: "ms", method: "rmssd"},
      blood_oxygen: {avg: 96.7, unit: "%"},
    },
  });
});

test("WHOOP skips naps, pending scores and undated recoveries", () => {
  assert.deepEqual(whoopVitals([{...sleep, nap: true}], [recovery]), {});
  assert.deepEqual(whoopVitals([], [recovery]), {});
  assert.deepEqual(whoopVitals([{...sleep, score_state: "PENDING_SCORE"}],
      [{...recovery, score_state: "PENDING_SCORE"}]), {});
  assert.deepEqual(whoopVitals([sleep]), {
    "2026-09-30": {respiratory_rate: {avg: 14.1, unit: "brpm"}},
  });
});

test("WHOOP retries are idempotent and latest scored revision wins", () => {
  const older = {...recovery, updated_at: "2026-10-01T02:00:00Z",
    score: {resting_heart_rate: 65}};
  const first = whoopVitals([sleep], [recovery, older]);
  assert.deepEqual(first, whoopVitals([sleep], [older, recovery]));
  assert.equal(first["2026-09-30"].resting_heart_rate.avg, 58);
});

test("Fitbit callable reads real reconcile shapes and keeps WHOOP priority",
    async (t) => {
      const admin = require("firebase-admin");
      const {syncFitbit} = require("../index");
      const writes = [];
      const existing = {
        resting_heart_rate: {avg: 60, source: "whoop"},
        hrv: {avg: 70, source: "apple_health"},
      };
      const snapshot = (data) => ({exists: true, data: () => data});
      const reference = (path) => ({
        path,
        collection: (name) => ({
          doc: (id) => reference(`${path}/${name}/${id}`),
        }),
        get: async () => snapshot({accessToken: "test-only",
          expiresAt: {toMillis: () => Date.now() + 3600000}}),
      });
      const db = admin.firestore();
      t.mock.method(db, "collection", (name) => ({
        doc: (id) => reference(`${name}/${id}`),
      }));
      t.mock.method(db, "runTransaction", async (callback) => callback({
        get: async () => snapshot({}),
        getAll: async (...references) => references.map((ref) => snapshot(
          ref.path.includes("metrics_daily") ? existing :
            {whoopConnected: true})),
        set: (ref, values, options) => writes.push({ref, values, options}),
      }));
      const requests = [];
      t.mock.method(global, "fetch", async (url) => {
        const parsed = new URL(url);
        requests.push(parsed);
        const type = parsed.pathname.split("/")[5];
        let dataPoints = [];
        if (type === "daily-resting-heart-rate") {
          dataPoints = [{dailyRestingHeartRate: {date, beatsPerMinute: "55"}}];
        } else if (type === "daily-heart-rate-variability") {
          dataPoints = [{dailyHeartRateVariability: {
            date, averageHeartRateVariabilityMilliseconds: 42,
          }}];
        } else if (type === "daily-respiratory-rate") {
          dataPoints = [{dailyRespiratoryRate: {date, breathsPerMinute: 14}}];
        }
        // Reconcile responses do not have dataSource.platform.
        return {ok: true, status: 200, json: async () => ({
          rollupDataPoints: [], dataPoints,
        })};
      });
      await syncFitbit.run({auth: {uid: "test"}, data: {daysBack: 1}});
      const saved = writes.find((write) =>
        write.ref.path.endsWith("metrics_daily/2026-10-01"));
      assert.ok(saved);
      assert.equal(saved.values.hrv_rmssd.avg, 42);
      assert.equal(saved.values.hrv_rmssd.source, "fitbit");
      assert.equal(saved.values.hrv, undefined);
      assert.equal(saved.values.resting_heart_rate, undefined);
      assert.equal(saved.values.respiratory_rate.avg, 14);
      assert.ok(saved.options.mergeFields.includes("hrv_rmssd"));
      const daily = requests.find((url) =>
        url.pathname.includes("daily-heart-rate-variability"));
      assert.equal(daily.searchParams.get("dataSourceFamily"),
          "users/me/dataSourceFamilies/google-wearables");
      assert.match(daily.searchParams.get("filter"),
          /daily_heart_rate_variability\.date >=/);
    });

for (const mode of ["no permission", "permission", "recovery fails"]) {
  test(`WHOOP vitals: ${mode}`, async (t) => {
    const hasVitalsPermission = mode !== "no permission";
    const vitalsSaved = mode === "permission";
    const admin = require("firebase-admin");
    const {syncWhoop} = require("../index");
    const credentials = {
      accessToken: "test-only",
      scope: hasVitalsPermission ? "read:sleep read:recovery" : "read:sleep",
      expiresAt: {toMillis: () => Date.now() + 3600000},
    };
    const writes = [];
    const snapshot = (path) => ({
      exists: !path.includes("metrics_daily"),
      data: () => path.startsWith("whoop_credentials") ? credentials : {},
    });
    const reference = (path) => ({path,
      get: async () => snapshot(path),
      collection: (name) => ({doc: (id) => reference(`${path}/${name}/${id}`)}),
    });
    const db = admin.firestore();
    t.mock.method(db, "collection", (name) => ({
      doc: (id) => reference(`${name}/${id}`),
    }));
    t.mock.method(db, "runTransaction", async (callback) => callback({
      get: async (ref) => snapshot(ref.path),
      getAll: async (...refs) => refs.map((ref) => snapshot(ref.path)),
      set: (ref, values) => {
        if (ref.path.startsWith("whoop_credentials")) {
          Object.assign(credentials, values);
        }
        writes.push({path: ref.path, values});
      },
      update: () => {},
    }));
    const endpoints = [];
    t.mock.method(global, "fetch", async (url) => {
      const path = new URL(url).pathname;
      endpoints.push(path);
      assert.ok(path.endsWith("/sleep") || path.endsWith("/recovery"));
      if (mode === "recovery fails" && path.endsWith("/recovery")) {
        return {ok: false, status: 500, json: async () => ({})};
      }
      return {ok: true, status: 200, json: async () => ({
        records: path.endsWith("/sleep") ? [sleep] : [recovery],
      })};
    });
    const result = await syncWhoop.run({auth: {uid: "test"},
      data: {daysBack: 1, force: true, timezoneOffsetMinutes: -360}});
    assert.equal(endpoints.some((path) => path.endsWith("/recovery")),
        hasVitalsPermission);
    const saved = writes.find((write) =>
      write.path.endsWith("metrics_daily/2026-09-30"));
    assert.ok(saved);
    assert.equal(saved.values.respiratory_rate.source, "whoop");
    assert.equal(saved.values.hrv_rmssd?.avg,
        vitalsSaved ? 44.3 : undefined);
    assert.equal(saved.values.recovery, undefined);
    assert.equal(saved.values.strain, undefined);
    assert.equal(result.endpoints.sleep, "synced");
    assert.equal(result.endpoints.vitals, {
      "no permission": "permission_required",
      "permission": "synced",
      "recovery fails": "failed",
    }[mode]);
  });
}
