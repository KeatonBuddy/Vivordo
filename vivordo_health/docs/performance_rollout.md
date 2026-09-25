# Performance rollout: cached metrics and compact activity summaries

Branch: `vivordo_performance`. This is a staged implementation, not a claim that
all performance work is finished. No production deployment, migration, or
reader activation is performed by building this branch.

## Implemented locally

- Home, My Day, and Fitness read metrics through `MetricsRepository`. Exact
  account/date-window/projection subscriptions are shared. Overlapping but
  different windows are **not** merged into one larger download.
- Subscriptions disconnect when their existing visibility-aware consumers
  disconnect. At most six inactive windows remain in memory. Reopening a window
  replays cached data, then reconciles the current snapshot, including deletions.
- Account changes clear repository data and terminate old subscriptions.
  This adds no new persistent health-data store; Firestore's existing disk cache
  policy is unchanged. Cached data is not assigned a new measurement timestamp.
- Fitness projects only the three activity totals and skips data notifications
  for unrelated metric changes. Missing readings remain distinct from zero.
- Home's derived-value cache keys off compact immutable day data. Home tiles
  extract only display fields; Home history extracts stress scalars and prepares
  heart-rate candidates only down to the newest usable day (not all 90 days).
  The generic full-document decode/deep-comparison/recursive-freeze path has
  been removed following the Sep 25 profile, which showed 100–417 ms stalls.
- My Day extracts sleep/stress scalars and prepares historical stress entries
  once per changed day. Normal clock lookups use binary search; duplicate
  timestamps retain legacy filter/sort tie behavior. Only today's heart-rate
  candidates are prepared. Existing formulas and baseline windows are unchanged.
- Profile/debug timeline spans identify metric projection, health sync (overall
  and per metric), and stress-payload preparation. They contain no user IDs or
  readings and are disabled in release. Async spans include waiting time; they
  are not a CPU-time measurement. Use the CPU profiler to attribute actual work.
- Projection spans now distinguish `metrics.extract.*`, `metrics.prepare.*`,
  `metrics.compare.*`, and `metrics.summary.*`. There is no `project.full` path.
  Field extraction avoids recursive Dart conversion of unrelated arrays but
  does **not** reduce Firestore's platform-channel or network payload size.
- An additive, **disabled-by-default** activity summary path, projector,
  resumable bounded backfill tool, and security tests are available.

No changes to scoring formulas, source precedence, goals, sleep aggregation,
sync cadence, or legacy `metrics_daily` writes are part of this stage.

## Compact contract and compatibility

`users/{uid}/metric_summaries_daily/{YYYY-MM-DD}` contains `schemaVersion: 1`,
`steps`, `active_calories`, `exercise_time` (each `{sum, source}`), and
`projectedAt`. The projector copies canonical totals rather than recalculating
them. `projectedAt` is processing time, **not** measurement freshness.

The Cloud Function `projectDailyActivitySummary` reads the current source inside
a transaction instead of using stale event data. Duplicate/out-of-order events
converge, removed fields are replaced, deleted days remove summaries, and account
deletion tombstones prevent delayed resurrection. Unchanged projections are not
rewritten. Failed invocations are retryable. Transactions read four documents
per attempt, so deployment adds invocation/read costs even for unrelated metric
writes; retries add cost too. Estimate those costs before deployment.

Old builds continue reading/writing their original documents. New rules only
reserve the two **new** summary/migration collections for server writes. They
must be excluded from the existing owner-write wildcard, not merely covered by
an additional `allow write: if false` rule.

Home and My Day intentionally still use detailed legacy data: a three-total
activity summary cannot replace source-aware heart-rate history or same-time
capacity baselines. Turning on activity summaries affects only Fitness.

## Local verification

From the Flutter project:

```sh
flutter test test/metrics_repository_test.dart test/fitness_activity_history_test.dart test/fitness_goal_insight_test.dart test/home_metrics_summary_test.dart test/daily_brief_metrics_test.dart test/daily_brief_analysis_test.dart test/daily_brief_card_test.dart test/visible_stream_builder_test.dart test/workout_card_updates_test.dart
flutter test test/screen_metric_projection_test.dart test/owned_stream_snapshot_test.dart
firebase emulators:exec --only firestore --project demo-vivordo-performance 'node functions/test/metrics_summary.emulator.js'
```

From `functions`, run `npm test`. Emulator tests explicitly require a local
emulator and fixed demo project; they exercise owner/cross-account/anonymous
reads, denied client creates/updates/deletes, preserved legacy writes, and real
transaction races. Unit tests are not substitutes for those emulator tests.

## Production rollout — separate approval required

1. Pass local tests and real-device parity/profile gates below. Leave the build
   flag off. Review expected function/read/write costs before proceeding.
2. Deploy the rules and **only** `projectDailyActivitySummary`. Do not deploy all
   unrelated functions as part of this rollout. Verify fresh writes/corrections
   and deletions reach the new collection in a test account.
3. Dry-run a bounded range (90 days maximum), then explicitly approve/apply it:

   ```sh
   node scripts/backfill_activity_summaries.js PROJECT UID YYYY-MM-DD YYYY-MM-DD
   node scripts/backfill_activity_summaries.js PROJECT UID YYYY-MM-DD YYYY-MM-DD --apply
   ```

   Commands run from `functions`. Dry-run makes no database calls. Apply uses
   operator credentials and the explicit project; it is not app startup work.
   Use one operator/run per account. The cursor resumes the same range; use
   `--restart` for a full reconciliation. Keep the live projector running during
   backfill. Source deletions and empty days are reconciled, not just copied.
4. Compare every day and all three canonical totals, including null/zero,
   changed/deleted days and multiple data sources. Verify the marker's bounded
   range covers the reader's entire 15-day window. The backfill finishes with
   `enabled: false`—completion alone is **not** verification or activation.
5. Only after verification set `enabled: true` on the server-owned
   `users/{uid}/metrics_summary_migrations/v1` marker, keeping `schemaVersion: 1`,
   `status: complete`, `startDay`, `endDay`. Opt a test build in with
   `--dart-define=VIVORDO_ACTIVITY_SUMMARIES=true`.
6. Verify cold/warm load, offline fallback, updates during sync, and rollback
   on devices before broader activation. Do not enable for production users
   until acceptable projection latency and lost-write recovery are demonstrated.

The reader checks the marker from the server with a three-second timeout on
subscription. Missing/disabled/incomplete/out-of-range markers use legacy data;
unknown document schema or query errors switch to legacy with only one active
source subscription. A valid empty summary window is treated as empty, not as a
reason to continually query both collections.

This first version has conservative **bounded** rollout coverage: a new day
beyond `endDay` falls back to legacy until the range is reconciled and verified
again. Do not extend the marker without verification. The server marker is not
a live listener; disabling it takes effect on the next subscription. Client
local writes are not optimistically overlaid onto server summaries yet; this
is another reason to keep the feature off until device validation.

Rollback: ship/run without the build flag (default), or disable the account
marker and reconnect the screen. Both restore legacy reads without deleting
data. If needed, separately stop the projector after readers are off to stop
its costs. Do not delete legacy documents or change their schema.

## Profiling and remaining stages

### Achievement client processing (Sep 25)

`AchievementInputsRepository` shares the lifetime metrics/workout inputs between
the monitor and reconciliation. Only `docChanges` are projected into small
per-day counts/totals and per-workout classifications. Reconciliation no longer
downloads these collections again, and unchanged achievement fields do not
produce timestamp-only writes. Relevant updates arriving during reconciliation
queue a trailing run; signed-out sessions are invalidated before new writes or
unlock announcements. Lifetime history, legacy scan/mood fallback rules, current
activity-goal comparisons, and earned-tier retention are unchanged.

This is a client-only stage. Firestore still sends full documents to these
listeners. Compact server achievement inputs, their versioned readiness gate,
backfill/parity audit, and deployment remain deferred. The activity-only V1
summary must not be used for achievement counts: it lacks mood and scan counts.

Tests: `flutter test test/achievement_inputs_test.dart
test/full_circle_achievement_test.dart test/mood_keeper_achievement_test.dart`.
New CPU spans: `Vivordo.achievements.project.metrics` and
`Vivordo.achievements.project.workouts`.

For the next CPU recording, disable **Track widget builds**, **Track layouts**,
and **Track paints** under Performance's Enhance tracing menu. In the Sep 25
00:42 export, about 46% of samples were in timeline event reporting, chiefly
per-render-object paint tracing. This instrumentation overhead must not be
mistaken for production rendering cost. Record at Medium CPU sampling while
syncing and scrolling, and check achievement progress after mood entries,
scans, workouts, historical deletions, goal changes, and account switching.

Run `flutter run --profile` on the same physical device and repeat cold launch,
warm Home/My Day/Fitness visits, continuous scrolling, workout set edits, manual
health refresh, background/resume, midnight rollover, and sign-out/sign-in.
Include accounts with long history and missing/partial health permissions.
Record CPU and timeline events when spikes occur; do not infer the responsible
plugin from a generic `DispatchPlatformMessage` span alone.

```sh
node scripts/profile_summary.js BEFORE.json AFTER.json
```

The script reports UI/raster percentiles and counts exceeding the device frame
budget, not just average FPS. Prior reference recording (Sep 24, 23:05, profile,
120 Hz): 1,601 frames in 45.19 s; UI p95 1.782 ms, p99 8.284 ms, max 21.705 ms,
16 over budget; raster p95 1.982 ms, max 10.708 ms, one over budget. This is a
**before** recording, not evidence of an improvement from this branch.

Sep 25 synthetic regression fixture: a 29-day window with large unused sensor
arrays visited 3,498,850 values through modeled legacy decode/freeze versus 8,602
through compact My Day extraction. One local run measured 327 ms versus 2 ms.
This is a deterministic traversal-count test with diagnostic host timings, not
a device benchmark or a prediction of on-device speed. New physical-device
profiling is still required, especially for remaining native message decoding.

Remaining work is gated on measurements and parity:

- Attribute the long native/platform-message bursts on device. Timeline spans
  added here are diagnostic, not a fix for native decoding.
- Define complete Home/My Day compact contracts including measurement times,
  source precedence, coverage, intraday stress semantics, and capacity baselines;
  then compare legacy and proposed outputs before switching readers.
- Add sync no-op write suppression only with correction/deletion/source-change
  tests. Do not silently omit data to reduce write counts.
- Move proven CPU-heavy pure transforms to isolates only if transfer overhead
  and end-to-end traces show a win. Plugin/Firestore calls stay on supported
  execution paths. Do not spawn an isolate per reading or per frame.
- Review BaaS history requirements before capping its payload query. Its current
  unbounded history behavior is unchanged here.

Do not claim release readiness or a measured speedup until the same device
scenarios are recorded after these changes and functional parity is confirmed.
