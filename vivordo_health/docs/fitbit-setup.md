# Fitbit on iOS through Google Health

Vivordo uses the Google Health API, which replaces the legacy Fitbit Web API.
The iOS app opens Google consent using `ASWebAuthenticationSession`. The
authorization code, access token, refresh token, and client secret stay in
Firebase Functions.

## Google Cloud configuration

In the same Google Cloud project used for the OAuth client:

1. Enable the **Google Health API**.
2. Configure the OAuth consent screen and request these scopes:
   - `googlehealth.activity_and_fitness.readonly`
   - `googlehealth.health_metrics_and_measurements.readonly`
   - `googlehealth.sleep.readonly`
3. Use a **Web application** OAuth client.
4. Add this authorized redirect URI, replacing the project ID if necessary:

   `https://us-central1-vivordo-health.cloudfunctions.net/googleHealthOAuthCallback`

The Google client ID ending in `apps.googleusercontent.com` is the value for
`GOOGLE_HEALTH_CLIENT_ID`. Download or copy the matching client secret from the
same Web application OAuth client.

## Firebase secrets and deployment

From `vivordo_health/`:

```sh
firebase functions:secrets:set GOOGLE_HEALTH_CLIENT_ID
firebase functions:secrets:set GOOGLE_HEALTH_CLIENT_SECRET
firebase deploy --only functions:beginFitbitConnection,functions:googleHealthOAuthCallback,functions:syncFitbit,functions:disconnectFitbit
```

The old `FITBIT_CLIENT_ID` and `FITBIT_CLIENT_SECRET` secrets are no longer
used and may be deleted after the migrated functions have deployed and tested.

## Data flow

1. `beginFitbitConnection` creates a short-lived, single-use OAuth state and
   returns Google's authorization URL.
2. Google redirects to the HTTPS `googleHealthOAuthCallback` function.
3. Firebase validates the state, exchanges the code, stores credentials in
   `google_health_credentials/{uid}`, and redirects back to the iOS scheme
   `vivordo-fitbit://oauth2redirect`.
4. `syncFitbit` requests daily Google wearable rollups and reconciled daily
   vitals/sleep. The `google-wearables` source family excludes Apple Health
   and manually logged data. Reconciled responses have no `dataSource` field;
   do not filter them by `dataSource.platform` after querying that family.
5. Fitbit active calories, distance, floors, heart rate, weight, and
   sleep are normalized into `users/{uid}/metrics_daily/{yyyy-MM-dd}` with
   `source: fitbit`. Sleep sessions are assigned to the day the user wakes and
   store total time asleep in hours. Active calories use Google Health's
   `active-energy-burned.kcalSum` and remain in Vivordo's existing
   `active_calories` field.
6. Resting heart rate, breathing rate and blood oxygen use Google's dated
   daily observations (not its personal-range rollups). HRV is stored as
   `hrv_rmssd`, with `method: rmssd`, separately from Apple Health's `hrv`
   SDNN data. The kinds are never converted or mixed: Capacity, Heart and
   burnout compare HRV only with earlier readings of the same kind
   (`functions/hrv.js`), preferring the wearable once it has 7 days.

Steps intentionally remain Apple Health-only. Exercise minutes are unchanged:
Google Active Zone Minutes can be intensity-weighted and must not be treated
as literal exercise duration or added to an already-imported workout.
Missing or unsupported vitals do not erase existing readings or become zero.
Connected WHOOP measurements retain priority over Fitbit for the same metric.

## WHOOP vitals expansion

WHOOP continues importing sleep and now imports breathing rate from scored
main sleeps, plus resting heart rate, HRV (RMSSD) and blood oxygen from the
recovery endpoint. **Recovery and Strain scores are not stored or used.**
Recovery records are assigned to their associated sleep's local wake date,
not the date they were uploaded. Missing sleep associations are skipped.

The new `read:recovery` permission is necessary to access those underlying
measurements, even though Vivordo does not use WHOOP's Recovery score.
New connections request `offline`, `read:sleep`, and `read:recovery`.
Older sleep-only connections still sync sleep/breathing rate; reconnecting
WHOOP (disconnect without deleting, then connect) grants the rest.
The existing morning/midday schedule and explicit 30-day sync are unchanged.

No WHOOP cycle totals are mapped to activity rings: cycle energy includes
basal calories and physiological cycles are not calendar days. Current body
measurements are not dated weight history. No synthetic intraday BPM is
generated, and existing live Bluetooth heart rate is unchanged.

### Deploy and verify

From `vivordo_health/` (these changes are not live until deployed):

```sh
firebase deploy --only functions:beginWhoopConnection,functions:whoopOAuthCallback,functions:syncWhoop,functions:disconnectWhoop,functions:syncFitbit
```

1. Test an existing sleep-only WHOOP connection, then grant the additional
   permission and sync 30 days. Compare local dates and measurements with WHOOP.
2. Sync Fitbit and compare RHR, SpO2, breathing rate and HRV with the
   device's recorded data. Availability depends on device and granted access.
3. Confirm `hrv` (SDNN) remains unchanged alongside `hrv_rmssd`.
4. Connect both providers: WHOOP wins overlapping vitals; Fitbit fills gaps.
5. Disconnect WHOOP with deletion enabled: WHOOP vitals are removed along with
   sleep/Bluetooth data; Apple Health and Fitbit fields are retained.

API contracts: [WHOOP v2](https://developer.whoop.com/api/),
[Google vitals](https://developers.google.com/health/data-types/vitals),
[Google reconciliation](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/reconcile).

The credential and OAuth-state collections are intentionally absent from
`firestore.rules`, so client SDKs cannot read them.
