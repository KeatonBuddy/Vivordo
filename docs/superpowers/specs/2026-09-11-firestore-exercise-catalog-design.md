# Firestore Exercise Catalog

Move the default exercise catalog from a compiled-in Dart constant to a single
Firestore document so it can be changed without an app release, and mark
user-created exercises distinctly in the picker.

## Problem

`fitness_screen.dart` holds 1,128 exercises as a `const _exerciseLibrary` block
(lines 3167-5854, roughly 2,700 of the file's 7,232 lines). Adding or correcting
one requires an app release. Separately, users can already
create their own exercises (`users/{uid}/custom_exercises`), but nothing in the
UI distinguishes those from the built-in list, and a user's handful of custom
lifts is unfindable among 1,128 alphabetically sorted defaults.

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Source of truth | Firestore only | The bundled copy stops being a second source that can drift. |
| Offline | Firestore SDK disk cache + in-memory copy | Persistence is on by default; nothing in the app clears it. |
| Document shape | One doc, flat ordered array | 1 read per launch instead of 1,128; preserves catalog order. |
| Editing | Seed script (Admin SDK) + Firebase console | No new endpoint, no admin auth surface. |
| Custom marker | Pinned section plus per-row badge | Discoverable while browsing, still identifiable inside search. |
| Custom-ness | Derived from source collection | No workout-history migration. |

## Data model

`exercise_catalog/current`:

```
{
  version:   int,        // bumped by the seed script; diagnostic only
  updatedAt: timestamp,
  exercises: [ { n: "Barbell Bench Press", c: "Chest" }, ... ]   // 1,128
}
```

Measured at 57KB against a 1MB document limit. Short field names (`n`, `c`)
keep the payload small; they are read in exactly one place.

**Array, not a category map.** `circle_screen` renders the catalog unsorted, in
catalog order. Firestore sorts map keys lexicographically rather than preserving
insertion order, so a `byCategory` map would silently reorder the Circle challenge picker from `Chest, Back, ...` to
`Arms, Back, ...`. A flat array preserves the existing order exactly and matches
the current Dart type one-to-one.

Security rules:

```
match /exercise_catalog/{document} {
  allow read: if request.auth != null;
  allow write: if false;
}
```

The seed script uses the Admin SDK and bypasses rules, so no client can write
the catalog.

## Components

### ExerciseCatalogService (new)

`lib/src/services/exercise_catalog_service.dart`

```dart
static Future<void> prefetch()                          // idempotent, never throws
static List<WorkoutExerciseCatalogItem> get defaults    // empty until loaded
static bool get isLoaded
```

Reads `exercise_catalog/current` once and holds the parsed list in memory.
Malformed, missing, or partially malformed documents yield the entries that did
parse (possibly none) rather than throwing; entries missing a name are skipped
and `c` defaults to `Other`.

`isLoaded` reports whether a document was actually read, and is distinct from
`defaults.isEmpty` — an empty catalog and a failed fetch must be
distinguishable, because one of them must block the back-fill below.

Called from `_AuthGateState`'s `_lastSyncedUid` block in `main.dart`, alongside
`NotificationService.configureForUser`. That block runs once per signed-in user,
so the cache is warm before the workout tracker is reachable. Fetching lazily on
picker open would leave "signed in at home, first workout at the gym" with an
empty list.

### WorkoutExerciseCatalogItem

The typedef and the derived `workoutExerciseCatalog` list move out of
`fitness_screen.dart` into the service. `circle_screen` currently imports both
from `fitness_screen` (a screen importing a screen for data) and will import
them from the service instead.

### fitness_screen

- The `const _exerciseLibrary` block (lines 3167-5854) is deleted;
  `_exerciseLibrary` becomes a view over `ExerciseCatalogService.defaults`.
  `fitness_screen.dart` drops from 7,232 to roughly 4,500 lines.
- `_ExerciseDefinition` gains `final bool isCustom` (default `false`), set true
  only for entries sourced from `custom_exercises`.
- `_ExercisePickerRow` renders a `CUSTOM` badge when `isCustom`.
- The picker shows `YOUR EXERCISES` above `ALL EXERCISES` when the search box is
  empty and the category filter is `All`; otherwise one `ALL EXERCISES` list,
  badges intact.

## The back-fill hazard

`_loadCustomExercises` currently recovers exercises from workout history,
treats anything absent from `_exerciseLibrary` as user-created, and **writes it
into `users/{uid}/custom_exercises`**.

Once defaults are remote, a failed or empty catalog load makes every default
exercise in a user's history look user-created. The back-fill would then
permanently write hundreds of defaults into that user's collection. This is
irreversible corruption of user data, not a display bug.

The back-fill must be skipped entirely unless `ExerciseCatalogService.isLoaded`
is true. This is the single most important correctness requirement in this
change and is covered by a dedicated test.

## Seeding

The 1,128 entries are extracted from the `const _exerciseLibrary` block, which is
then deleted, and become `functions/scripts/exercise_catalog_seed.json` - the
catalog's source of truth in git.

`functions/scripts/seed_exercise_catalog.js` reads that JSON, writes
`exercise_catalog/current`, and bumps `version`. Run for the initial upload and
after any bulk edit. Single additions and corrections happen in the Firebase
console; the JSON must be updated to match, or the next seed run will revert
them. See Renaming defaults before renaming anything.

## Firebase-side changes

Everything below happens outside the app, against project `vivordo-health`.
Nothing here needs a new Firebase product; Firestore is already in use.

### One-time, at deploy

1. **Publish the security rule.** Add the `exercise_catalog` block to
   `vivordo_health/firestore.rules`, then from `vivordo_health/`:

   ```
   firebase deploy --only firestore:rules --project vivordo-health
   ```

   Until this is deployed the catalog is unreadable and every client falls back
   to an empty list, so deploy the rule before shipping the app build.

2. **Seed the catalog document.** The script authenticates with the Admin SDK.
   Prefer application-default credentials so no long-lived key file exists:

   ```
   gcloud auth application-default login
   cd vivordo_health/functions
   node scripts/seed_exercise_catalog.js
   ```

   The script is dry-run by default: it prints what it would write and writes
   nothing. Review that output, then run it again with `--apply` to actually
   write the document:

   ```
   node scripts/seed_exercise_catalog.js --apply
   ```

   If gcloud is unavailable, download a service account key from
   Firebase console > Project settings > Service accounts, point
   `GOOGLE_APPLICATION_CREDENTIALS` at it, and run the same commands. That key
   is a production credential: it must not be committed, and should be deleted
   once the seed is done.

   The `--apply` run creates `exercise_catalog/current`. Verify in
   Firebase console > Firestore Database that the document exists and
   `exercises` has 1,128 entries.

**No index is required.** The client does a single document `get()` by known
path, never a query, so `firestore.indexes.json` is unchanged.

### Ordering constraint between rule, seed, and app release

The rule and the seed must both be live before the app build that depends on
them reaches users. An app that can read nothing shows an empty exercise picker.
The reverse order is harmless: the catalog document can exist for as long as you
like before any client reads it.

### Ongoing, to change the exercise list

Firebase console > Firestore Database > `exercise_catalog` > `current` > edit
`exercises`, then increment `version`. Clients pick the change up on their next
launch. No app release, no redeploy.

Mirror the same edit into `functions/scripts/exercise_catalog_seed.json` and
commit it. The seed file is authoritative: the next `seed_exercise_catalog.js`
run overwrites the document, silently reverting any console edit that was not
mirrored back.

For bulk changes, edit the JSON and re-run the seed script instead of hand-editing
the console.

### Cost

One document read per user per app launch, against a document of roughly 57KB.
At Firestore's read pricing this is immaterial at any plausible user count, and
it replaces zero reads today, so it is a real but very small increase.

## Renaming defaults

Workouts store exercises by name string (`WorkoutExerciseRecord.name`), and
personal bests and `loadLatestExerciseSets` key off `name.toLowerCase()`.
Renaming an exercise in the catalog orphans existing history for that lift: past
sets stop matching, and the exercise reappears in the picker under its new name
with no history.

This change does not add rename migration. Renames are safe only for exercises
no one has logged. Additions and removals are safe; a removed exercise stays
visible in past workouts because history stores the name, not a reference.

## Testing

| Test | Asserts |
|---|---|
| catalog parse | well-formed document yields items in document order |
| catalog parse | missing document and malformed entries yield no throw |
| `isLoaded` | false after a failed fetch, true after an empty-but-present document |
| back-fill guard | no writes to `custom_exercises` when `isLoaded` is false |
| picker sectioning | custom entries in the top section while browsing |
| picker sectioning | one merged, badged list once a search or filter is active |
| seed script | `node --test` over the JSON to document-shape transform |

## Out of scope

- Editing or deleting default exercises from the app.
- Per-exercise metadata (equipment, muscle group, media).
- Rename migration for logged history.
- Reading `version` on the client to gate refresh. One document read per launch
  is cheaper than a version check; the field is kept for diagnostics.
