# Vivordo Health on Android — design

## Intent

Vivordo Health is on TestFlight and about to ship to the App Store. The same app
must ship on Google Play: same login, notifications, AI assistant, health data,
integrations and screens. One codebase (`vivordo_health/`), one repo, two builds
(`.ipa` for Apple, `.aab` for Google Play). Platform differences stay as small
`Platform.isIOS` / `isAndroid` checks or one platform file per feature, never a
parallel app.

## Goals

- **Phase 1 — Play-ready Android build** with every feature except the four
  iOS-native extras below. Runs on the user's emulators (`Pixel_10_Pro`,
  `Medium_Phone_API_37.0`) and is signed for Play Store upload.
- **Phase 2 — Android versions of the iOS-native extras, one at a time**, each
  its own small change, tested on the emulator before the next starts.

## Non-goals

- No redesign for Material/Android look. The app keeps its current UI on both
  platforms (it already renders its own widgets; `liquid_glass_renderer` is used
  in one file and must simply not crash on Android).
- No separate repo, flavor, or Android-only fork of screens.
- No Play Store listing, screenshots or store copy (user's job; checklist only).

## Anti-goals (failure even if Android works)

- Any change in iOS behavior or anything that risks the App Store submission.
  Every change must leave `flutter build ios` and current iOS flows untouched.
- Android features that silently fail (e.g. notifications never prompting,
  Google button doing nothing). A missing feature must be absent from the UI,
  not broken.

## Current state (from recon)

Already cross-platform, no work: Firebase (Auth email/Google, Firestore,
Functions, Remote Config, Storage, Crashlytics, Messaging), the `health` plugin
(uses Health Connect on Android; onboarding already says "Health Connect"),
Sign in with Apple already hidden off-iOS, home widgets / VO2 max / sleep
observer / Live Activities already no-op off-iOS. Server push payloads already
carry `android:` blocks in several functions.

## Phase 1 work

1. **App identity.** Android `applicationId` and `namespace`
   `com.example.vivordo_health` → `com.vivordo.health` (matches iOS); move
   `MainActivity.kt` to the matching package. App label "Vivordo"; launcher
   icon generated from `assets/app_icon.png` (`flutter_launcher_icons`,
   `android: true`).
2. **Firebase Android app.** *User:* register Android app `com.vivordo.health`
   in Firebase project 226030806435, add debug + upload-key SHA-1/SHA-256,
   download new `google-services.json`. *Builder:* drop it in, update
   `firebase_options.dart` android block (or rerun `flutterfire configure`).
3. **Manifest permissions & components:** `INTERNET`, `POST_NOTIFICATIONS`,
   Health Connect read permissions for the data types `health_service.dart`
   requests plus the Health Connect permissions-rationale activity alias and
   `<queries>` entry, `CAMERA`, `USE_BIOMETRIC`, and what
   `flutter_local_notifications` needs for scheduled notifications (boot
   receiver, exact-alarm handling).
4. **Notification permission bug.** `NotificationService.requestPermission()`
   returns `true` on Android without asking. On Android it must request the
   permission (Android 13+) and return the real result. iOS path unchanged.
5. **OAuth return links.** Register `vivordo-whoop` and `vivordo-fitbit`
   callback schemes for `flutter_web_auth_2` on Android.
6. **Outlook calendar.** Add `androidConfig` to `SingleAccountPca.create` and
   the MSAL redirect activity/config. *User:* add the Android redirect URI
   (package + signature hash) in Azure app `07c05b6e-…`.
7. **Release signing.** Release build signs with an upload key read from
   `android/key.properties` (git-ignored), falling back to debug when absent so
   `flutter run --release` keeps working locally. *User:* create the upload
   keystore and keep it backed up.
8. **Build settings.** Raise `minSdk` to whatever Health Connect / plugins
   require (expected 26); check Gradle/Kotlin/AGP versions build cleanly.
9. **Verify on emulator:** email signup/login, Google sign-in, onboarding incl.
   Health Connect permission, push + scheduled local notifications, AI chat,
   WHOOP/Fitbit connect redirect, Outlook connect, camera/scan, image picker,
   biometric lock. Then `flutter build appbundle --release` succeeds, and
   `flutter build ios` still succeeds.

## Phase 2 — Android equivalents, one at a time (order is the builder's call
unless the user says otherwise)

| iOS feature | Android equivalent |
|---|---|
| Home-screen widgets (`home_widget_service.dart`) | Android App Widgets fed by the same data the iOS widget gets |
| Workout Live Activity | Ongoing workout notification (progress-style / Live Update on newer Android) |
| Siri shortcuts (`VivordoSiri.swift`) | Android app shortcuts / App Actions |
| VO2 max (`vo2_max_service.dart`, native HealthKit) | Read VO2 max from Health Connect |
| WHOOP live Bluetooth heart rate | Same `flutter_reactive_ble` code on Android + Bluetooth permissions; needs a real phone and WHOOP to test |

Each removes its `!Platform.isIOS` guard only for the parts it implements and
reuses the existing Dart service and MethodChannel name.

10. **Hide WHOOP live Bluetooth heart rate on Android** (user decision).
    `whoop_ble_heart_rate_service.dart` already refuses off-iOS; hide the live
    card / pair flow in `heart_rate_detail_screen.dart` (and anywhere else it
    is offered) on Android. WHOOP cloud data via OAuth stays. No Bluetooth
    permissions in Phase 1.
11. **Push sound (builder's call).** `functions/push.js` has no `android:` block
    (notifications still arrive, silently). Add
    `android: {notification: {sound: "default"}}` like the other senders;
    needs a functions deploy. No function filters by platform.

## User checklist (only they can do)

- Firebase: add Android app + SHA fingerprints (debug, upload key, **and the
  Play App Signing key** from Play Console — Play re-signs installs), send
  `google-services.json`.
- Azure: Android redirect URIs for Outlook — one per signature hash (debug and
  Play signing key). Builder's call: per-build-type MSAL config.
- Remote Config: add an Android condition on `update_url` pointing at the Play
  listing, so force-update doesn't send Android users to the App Store.
- Upload keystore + `key.properties`.
- Google Play Console account, app listing, Health Connect declaration form
  (Play requires it for health permissions), data-safety form.

## Left to the builder

Exact permission list (derived from code), minSdk value, Gradle version bumps,
whether to use `flutterfire configure` or edit by hand, Phase 2 order.
