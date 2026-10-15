# Android Port — Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Play-ready Android build of Vivordo Health from the existing Flutter codebase, with every feature except the iOS-native extras (widgets, Live Activity, Siri, VO2 max, WHOOP live Bluetooth).

**Architecture:** One codebase. Android config lives in `vivordo_health/android/`; Dart differences are `defaultTargetPlatform` checks in the service or screen that owns the feature (the house style — see `login_screen.dart:28`). iOS code paths are never edited except where a check now branches.

**Tech Stack:** Flutter 3 / Dart 3.9, AGP 8.9.1, Kotlin 2.1, Firebase, `health` 12.x (Health Connect), `flutter_local_notifications`, `flutter_web_auth_2`, `msal_auth` 3.x.

**Spec:** `docs/superpowers/specs/2026-10-15-android-port-design.md`

All paths below are relative to `vivordo_health/` unless they start with `docs/`.

## Global Constraints

- Android `applicationId` and `namespace`: `com.vivordo.health`. Kotlin package of `MainActivity`: `com.vivordo.health`.
- App label on Android: `Vivordo`.
- iOS behavior unchanged: `flutter build ios --no-codesign` must still succeed after every task that touches Dart.
- A feature unavailable on Android is absent from the UI, never a button that fails.
- No UI redesign; no new dependencies.
- No Bluetooth permissions in Phase 1.
- `android/key.properties` and any `*.jks`/`*.keystore` are git-ignored.
- Firestore metric keys (`steps`, `hrv`, `distance`, …) stay the same on both platforms.

## Review Focus

1. **Health Connect permission denied or partially granted** → app keeps working with the granted metrics, no crash, no endless re-prompt. Test in Task 3 (`authorizationTypes` excludes nothing iOS needs; emulator check in Task 8).
2. **User denies notification permission on Android 13+** → `requestPermission()` returns `false` and onboarding continues. Emulator check in Task 4.
3. **Android system back button / back gesture** on every pushed screen and sheet → pops like the iOS swipe, never exits the app from a nested screen. Emulator check in Task 8.
4. **Google sign-in from a build whose SHA-1 isn't registered** → shows the existing error message, doesn't hang. Emulator check in Task 8 (release build before Play key is registered).
5. **Opening heart-rate detail on Android with WHOOP connected** → no live card, no Bluetooth scan, no uncaught `StateError`. Test in Task 5.

---

### Task 0: User prerequisites (human, blocks Task 1 build step)

- [ ] Firebase console, project `226030806435`: add Android app `com.vivordo.health`; add the debug SHA-1/SHA-256 (`cd android && ./gradlew signingReport`, variant `debug`). Download `google-services.json`.
- [ ] Create the upload keystore (Task 6 gives the command) and add its SHA-1/SHA-256 to the same Firebase Android app.
- [ ] Remote Config: Android condition on `update_url` → Play listing URL (before the first forced update).
- [ ] Later, after first Play upload: add the **Play App Signing** SHA-1/SHA-256 from Play Console → Firebase, and its signature hash → Azure (Task 7).

### Task 1: App identity and Firebase

**Files:**
- Modify: `android/app/build.gradle.kts` (`namespace`, `applicationId`, `minSdk`)
- Move: `android/app/src/main/kotlin/com/example/vivordo_health/MainActivity.kt` → `android/app/src/main/kotlin/com/vivordo/health/MainActivity.kt` (package line `com.vivordo.health`; keep `FlutterFragmentActivity` — `local_auth` needs it)
- Replace: `android/app/google-services.json` (from Task 0)
- Modify: `lib/firebase_options.dart` android block (`appId` and any changed keys from the new `google-services.json`)
- Modify: `android/app/src/main/AndroidManifest.xml` (`android:label="Vivordo"`)
- Modify: `pubspec.yaml` `flutter_launcher_icons` → `android: true`, `adaptive_icon_background: "#FFFFFF"`, `adaptive_icon_foreground: "assets/app_icon.png"`

- [ ] **Step 1:** Set `minSdk = 26` (Health Connect floor; raise only if a plugin's Gradle error demands it).
- [ ] **Step 2:** `dart run flutter_launcher_icons` — Expected: new `android/app/src/main/res/mipmap-*/ic_launcher*.png`; `git diff --stat ios/` shows no changes (iOS icons are regenerated identically — if they differ, revert `ios/` changes).
- [ ] **Step 3:** `flutter build apk --debug` — Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`. A "No matching client found for package name" error means Task 0's `google-services.json` is missing.
- [ ] **Step 4:** `flutter emulators --launch Pixel_10_Pro`, then `flutter run -d emulator-5554` — Expected: app opens to the login screen, launcher shows "Vivordo" with the app icon.
- [ ] **Step 5:** Commit `chore(android): com.vivordo.health app id, label, icon`.

### Task 2: Manifest permissions and components

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1:** Add permissions: `INTERNET`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `CAMERA`, `USE_BIOMETRIC`, and Health Connect reads `android.permission.health.READ_` + `STEPS`, `ACTIVE_CALORIES_BURNED`, `DISTANCE`, `HEART_RATE`, `RESTING_HEART_RATE`, `HEART_RATE_VARIABILITY`, `OXYGEN_SATURATION`, `RESPIRATORY_RATE`, `SLEEP`, `WEIGHT`, `BODY_FAT`. (Exactly the Android types Task 3 requests — keep the two lists in sync.)
- [ ] **Step 2:** Add Health Connect components per the `health` package README: `<queries><package android:name="com.google.android.apps.healthdata"/></queries>`, the `ACTION_SHOW_PERMISSIONS_RATIONALE` intent-filter on `MainActivity`, and the `ViewPermissionUsageActivity` activity-alias with `android.intent.action.VIEW_PERMISSION_USAGE` / `android.intent.category.HEALTH_PERMISSIONS`.
- [ ] **Step 3:** Add `flutter_local_notifications` boot receivers (`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` with `BOOT_COMPLETED`/`MY_PACKAGE_REPLACED`) per its README. No exact-alarm permission — all schedules use `AndroidScheduleMode.inexactAllowWhileIdle`.
- [ ] **Step 4:** Add `flutter_web_auth_2`'s `com.linusu.flutter_web_auth_2.CallbackActivity` (`exported="true"`) with two `<data android:scheme>` intent-filters: `vivordo-whoop` and `vivordo-fitbit` (from `whoop_service.dart:20`, `fitbit_service.dart:22`).
- [ ] **Step 5:** `flutter build apk --debug` — Expected: builds; `flutter run` launches.
- [ ] **Step 6:** Commit `chore(android): permissions, Health Connect, notification and OAuth components`.

### Task 3: Health Connect data types

**Files:**
- Modify: `lib/src/services/health_service.dart` (`HealthMetricDef`, `_authorizationTypes`, and every place that reads `metric.type`)
- Test: `test/health_platform_types_test.dart`

**Interfaces:**
- Produces: `HealthDataType? get platformType` on `HealthMetricDef` — the type to request/read on the current platform; `null` = not available here (skip the metric).

Android mapping (all others unchanged): `distance` → `HealthDataType.DISTANCE_DELTA`, `hrv` → `HealthDataType.HEART_RATE_VARIABILITY_RMSSD`, `exercise_time` → `null`.

- [ ] **Step 1: Write the failing test**

```dart
test('Android swaps iOS-only health types', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  expect(kMetricByKey['distance']!.platformType, HealthDataType.DISTANCE_DELTA);
  expect(kMetricByKey['hrv']!.platformType, HealthDataType.HEART_RATE_VARIABILITY_RMSSD);
  expect(kMetricByKey['exercise_time']!.platformType, isNull);
  expect(kMetricByKey['steps']!.platformType, HealthDataType.STEPS);
  debugDefaultTargetPlatformOverride = null;
});

test('iOS keeps HealthKit types', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  for (final m in kHealthMetrics) {
    expect(m.platformType, m.type);
  }
  debugDefaultTargetPlatformOverride = null;
});
```

- [ ] **Step 2:** `flutter test test/health_platform_types_test.dart` — Expected: FAIL, `platformType` not defined.
- [ ] **Step 3:** Implement `platformType` with a `const` key→type override map used only when `defaultTargetPlatform == TargetPlatform.android`. Replace `metric.type` with `metric.platformType` in authorization and reads, skipping metrics where it is `null`. Results are still written under the metric's `key`. HRV: RMSSD and SDNN differ in scale — add `// shortcut: Android HRV is RMSSD, not SDNN; stress thresholds tuned on SDNN, recalibrate if Android stress scores look off.`
- [ ] **Step 4:** `flutter test` — Expected: new tests PASS, full suite still green.
- [ ] **Step 5:** On emulator (install/open Health Connect, add sample steps + heart rate): finish onboarding's Health Connect step — Expected: Health Connect permission sheet lists the Task 2 types; dashboard shows the sample steps.
- [ ] **Step 6:** Commit `feat(android): read Health Connect types`.

### Task 4: Ask for notification permission on Android

**Files:**
- Modify: `lib/src/services/notification_service.dart:437`

- [ ] **Step 1:** Change the guard to `if (kIsWeb) return true;` so `FirebaseMessaging.requestPermission` also runs on Android (it shows the Android 13+ system prompt and returns the real status). Update the doc comment from "Asks iOS" to "Asks the OS".
- [ ] **Step 2:** On the emulator, fresh install → onboarding's last step — Expected: Android notification prompt appears. Deny → onboarding continues. Re-install and allow → send a test message from Firebase console → Cloud Messaging to the device token; Expected: notification shows in the shade with app icon.
- [ ] **Step 3:** Verify a scheduled local notification (e.g. a priority reminder 1–2 min out) fires on the emulator.
- [ ] **Step 4:** Commit `fix(android): request notification permission`.

### Task 5: Hide WHOOP live Bluetooth on Android

**Files:**
- Modify: `lib/src/services/whoop_ble_heart_rate_service.dart` (add getter; `_ensurePlatformSupport` and `startIfPaired` use it)
- Modify: `lib/screens/heart_rate_detail_screen.dart:283` (card condition)
- Test: `test/whoop_ble_platform_test.dart`

**Interfaces:**
- Produces: `static bool get isSupported` on `WhoopBleHeartRateService` — `defaultTargetPlatform == TargetPlatform.iOS`.

- [ ] **Step 1: Write the failing tests**

```dart
test('live WHOOP Bluetooth is iOS-only', () {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  expect(WhoopBleHeartRateService.isSupported, isFalse);
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  expect(WhoopBleHeartRateService.isSupported, isTrue);
  debugDefaultTargetPlatformOverride = null;
});

test('startIfPaired is a silent no-op on Android', () async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await expectLater(WhoopBleHeartRateService.instance.startIfPaired(), completes);
  debugDefaultTargetPlatformOverride = null;
});
```

- [ ] **Step 2:** `flutter test test/whoop_ble_platform_test.dart` — Expected: FAIL, `isSupported` not defined.
- [ ] **Step 3:** Add `isSupported`; first line of `startIfPaired`: `if (!isSupported) return;`; `_ensurePlatformSupport` checks `isSupported`; card condition becomes `if (WhoopBleHeartRateService.isSupported && hasConnectedWearable && _wearableCollapsed != null)`. WHOOP cloud data (OAuth) is untouched.
- [ ] **Step 4:** `flutter test` — Expected: all PASS.
- [ ] **Step 5:** Commit `feat(android): hide WHOOP live Bluetooth card`.

### Task 6: Release signing

**Files:**
- Modify: `android/app/build.gradle.kts` (`signingConfigs`, `buildTypes.release`)
- Modify: `android/.gitignore` (add `key.properties`, `*.jks`, `*.keystore` if missing)

- [ ] **Step 1:** Read `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) when it exists into a `release` signing config; `release` build type uses it, else falls back to `debug` (keeps `flutter run --release` working).
- [ ] **Step 2:** Give the user the keystore command: `keytool -genkey -v -keystore %USERPROFILE%\vivordo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, and the `key.properties` template. Remind: back up the keystore; losing it means a Play key reset.
- [ ] **Step 3:** With `key.properties` present: `flutter build appbundle --release` — Expected: `✓ Built build/app/outputs/bundle/release/app-release.aab`. `git status` shows no keystore or `key.properties`.
- [ ] **Step 4:** Commit `chore(android): release signing from key.properties`.

### Task 7: Outlook calendar on Android

**Files:**
- Create: `assets/msal_config_debug.json`, `assets/msal_config_release.json` (`client_id` `07c05b6e-07ad-4ed3-bfd2-35af418decdf`, `authorization_user_agent: "DEFAULT"`, `account_mode: "SINGLE"`, `redirect_uri: "msauth://com.vivordo.health/<url-encoded signature hash>"`, authority `AzureADandPersonalMicrosoftAccount`)
- Modify: `pubspec.yaml` assets (both files)
- Modify: `lib/src/services/outlook_calendar_service.dart:107` — add `androidConfig: AndroidConfig(configFilePath: kReleaseMode ? 'assets/msal_config_release.json' : 'assets/msal_config_debug.json', redirectUri: …)` next to the existing `appleConfig`
- Modify: `android/app/src/main/AndroidManifest.xml` — MSAL `com.microsoft.identity.client.BrowserTabActivity` with `msauth` scheme, host `com.vivordo.health`, path `/<signature hash>` (debug via `src/debug/AndroidManifest.xml`, release hash in `src/main`)

- [ ] **Step 1:** Get hashes: `keytool -exportcert -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android | openssl sha1 -binary | openssl base64` (debug); release = Play App Signing key hash from Play Console. Until the Play key exists, the release file uses the upload-key hash — mark with `// shortcut: release redirect uses upload-key hash; switch to Play App Signing hash after first Play upload.` in the service.
- [ ] **Step 2:** User adds both redirect URIs in Azure → app `07c05b6e-…` → Authentication → Android platform.
- [ ] **Step 3:** Debug build on emulator: Settings → connect Outlook — Expected: Microsoft login opens in a browser tab, returns to the app connected; calendar events appear.
- [ ] **Step 4:** Commit `feat(android): Outlook calendar sign-in`.

### Task 8: Push sound + full emulator pass

**Files:**
- Modify: `functions/push.js:25` — add `android: {notification: {sound: "default"}},` beside `apns`

- [ ] **Step 1:** `cd functions && npm test` — Expected: PASS.
- [ ] **Step 2:** Walk the app on `Pixel_10_Pro` (debug) and record pass/fail for each: email signup → verification → login; Google sign-in; onboarding incl. Health Connect + notifications; AI assistant chat and saving a suggested workout routine; WHOOP connect (OAuth redirect returns to app); Fitbit connect; Outlook connect; Google Calendar; camera scan; image picker (profile photo); biometric lock (enroll a fingerprint in emulator settings first); Circle screens; dark mode; system back on every nested screen (Review Focus 3); force-update gate opens a URL.
- [ ] **Step 3:** Repeat login + dashboard on `Medium_Phone_API_37.0` (smaller screen layout).
- [ ] **Step 4:** Fix any failure as its own commit with root cause in the message; Android-only fixes use the platform-check style of the owning file.
- [ ] **Step 5:** `flutter build appbundle --release` and `flutter build ios --no-codesign` — Expected: both succeed.
- [ ] **Step 6:** `cd .. && graphify update .`
- [ ] **Step 7:** Commit `fix(push): android notification sound` (+ any pass fixes). Deploy of `push.js` is the user's call: `firebase deploy --only functions`.

## Phase 2

Each extra (widgets, workout ongoing notification, app shortcuts, VO2 max via Health Connect, WHOOP live Bluetooth) gets its own short plan after Phase 1 ships, in the order the user picks.
