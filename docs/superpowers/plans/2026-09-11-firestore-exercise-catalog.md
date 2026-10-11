# Firestore Exercise Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve the 1,128 default exercises from a single Firestore document instead of a compiled-in Dart constant, and mark user-created exercises distinctly in the picker.

**Architecture:** A single document `exercise_catalog/current` holds a flat ordered array of `{n, c}` entries. `ExerciseCatalogService` reads it once after sign-in and holds the parsed list in memory; Firestore's default disk cache serves it offline. Pure parsing and back-fill-decision logic live in `lib/src/utils/` so they are testable without Firestore, matching the pattern already used by the twenty tested utils in that directory.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12.2, `cloud_firestore` ^6.1.0, `firebase-admin` ^13.6.0 on Node 24 for the seed script. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-11-firestore-exercise-catalog-design.md`

## Global Constraints

- Firebase project is `vivordo-health`. All Firebase commands run from `vivordo_health/`.
- Flutter commands need the SDK on PATH: `export PATH="$HOME/source/flutter/bin:$PATH"`.
- Baseline to preserve: `flutter analyze` reports **0 errors** (28 warnings, 188 info are pre-existing); `flutter test` reports **186 passing**. Every task must hold 0 errors and a non-decreasing test count.
- Do not reformat files that are already `dart format`-dirty on `robs_testing` (`fitness_screen.dart` is one). Run `dart format` only on files you create, and on files you edit that were format-clean before your edit.
- `lib/screens/profile_screen.dart` uses CRLF line endings. No task here touches it; if that changes, preserve CRLF.
- No new pub or npm dependencies.
- Cloud Functions lint is `eslint-config-google`: double-quoted strings, 2-space indent, required trailing commas in multiline literals. `npm --prefix functions run lint` must pass.
- Exercise names are user-visible copy. Never alter the 1,128 names or their order during extraction.

---

### Task 1: Catalog parsing and shared types

Pure functions with no Firestore dependency, so the parsing rules are testable directly.

**Files:**
- Create: `vivordo_health/lib/src/utils/exercise_catalog.dart`
- Test: `vivordo_health/test/exercise_catalog_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `typedef WorkoutExerciseCatalogItem = ({String name, String category});`, `String exerciseNameKey(String value)`, `List<WorkoutExerciseCatalogItem> parseExerciseCatalog(Map<String, dynamic>? data)`.

- [ ] **Step 1: Write the failing test**

Create `vivordo_health/test/exercise_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_catalog.dart';

void main() {
  test('parses entries in document order', () {
    final items = parseExerciseCatalog({
      'version': 1,
      'exercises': [
        {'n': 'Barbell Bench Press', 'c': 'Chest'},
        {'n': 'Barbell Row', 'c': 'Back'},
      ],
    });

    expect(items, hasLength(2));
    expect(items.first.name, 'Barbell Bench Press');
    expect(items.first.category, 'Chest');
    expect(items.last.name, 'Barbell Row');
  });

  test('returns empty for a null or malformed document', () {
    expect(parseExerciseCatalog(null), isEmpty);
    expect(parseExerciseCatalog({}), isEmpty);
    expect(parseExerciseCatalog({'exercises': 'not a list'}), isEmpty);
  });

  test('skips unusable entries but keeps the rest', () {
    final items = parseExerciseCatalog({
      'exercises': [
        {'n': 'Good Lift', 'c': 'Chest'},
        {'n': '   ', 'c': 'Chest'},
        {'c': 'Chest'},
        'not a map',
        {'n': 'Another Lift'},
      ],
    });

    expect(items.map((e) => e.name), ['Good Lift', 'Another Lift']);
    expect(items.last.category, 'Other', reason: 'missing category defaults');
  });

  test('trims surrounding whitespace on names and categories', () {
    final items = parseExerciseCatalog({
      'exercises': [
        {'n': '  Sled Push  ', 'c': '  Legs  '},
      ],
    });

    expect(items.single.name, 'Sled Push');
    expect(items.single.category, 'Legs');
  });

  test('exerciseNameKey ignores case, spacing and punctuation', () {
    expect(exerciseNameKey('Barbell Bench Press'), 'barbellbenchpress');
    expect(exerciseNameKey('barbell-bench  press'), 'barbellbenchpress');
    expect(exerciseNameKey('!!!'), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/source/flutter/bin:$PATH"
cd vivordo_health && flutter test test/exercise_catalog_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:vivordo_health/src/utils/exercise_catalog.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `vivordo_health/lib/src/utils/exercise_catalog.dart`:

```dart
/// One exercise offered by the workout builder.
typedef WorkoutExerciseCatalogItem = ({String name, String category});

/// Identity key for an exercise name. Case, spacing and punctuation are
/// ignored so "Barbell Bench Press" and "barbell-bench press" are one exercise.
String exerciseNameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Reads the `exercise_catalog/current` document body.
///
/// Order is preserved: the Circle challenge picker renders the catalog
/// unsorted, so the stored order is what users see.
///
/// Never throws. A missing or malformed document yields an empty list, and a
/// single unusable entry is skipped rather than discarding the whole catalog.
/// Callers must not treat an empty result as "the catalog loaded and is
/// empty" — see ExerciseCatalogService.isLoaded.
List<WorkoutExerciseCatalogItem> parseExerciseCatalog(
  Map<String, dynamic>? data,
) {
  final raw = data?['exercises'];
  if (raw is! List) return const [];

  final items = <WorkoutExerciseCatalogItem>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = (entry['n'] as String? ?? '').trim();
    if (name.isEmpty) continue;
    final category = (entry['c'] as String? ?? '').trim();
    items.add((name: name, category: category.isEmpty ? 'Other' : category));
  }
  return List.unmodifiable(items);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vivordo_health && flutter test test/exercise_catalog_test.dart
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd vivordo_health
dart format lib/src/utils/exercise_catalog.dart test/exercise_catalog_test.dart
flutter analyze 2>&1 | grep -c "error •"   # expect 0
cd .. && git add vivordo_health/lib/src/utils/exercise_catalog.dart vivordo_health/test/exercise_catalog_test.dart
git commit -m "Add exercise catalog parsing"
```

---

### Task 2: ExerciseCatalogService

Holds the fetched catalog in memory. `isLoaded` must be distinguishable from an empty list, because Task 3 gates destructive writes on it.

**Files:**
- Create: `vivordo_health/lib/src/services/exercise_catalog_service.dart`
- Test: `vivordo_health/test/exercise_catalog_service_test.dart`

**Interfaces:**
- Consumes: `parseExerciseCatalog`, `WorkoutExerciseCatalogItem` from Task 1.
- Produces: `ExerciseCatalogService.prefetch()`, `ExerciseCatalogService.defaults`, `ExerciseCatalogService.isLoaded`, `ExerciseCatalogService.loadForTesting(...)`, `ExerciseCatalogService.resetForTesting()`. Re-exports `exercise_catalog.dart`, so importers get the typedef from this file.

- [ ] **Step 1: Write the failing test**

The Firestore round-trip is not unit-tested (no fake-firestore dependency is available and none is being added); Task 1 covers parsing and this covers the state machine that Task 3 depends on.

Create `vivordo_health/test/exercise_catalog_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/exercise_catalog_service.dart';

void main() {
  setUp(ExerciseCatalogService.resetForTesting);

  test('starts empty and not loaded', () {
    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(ExerciseCatalogService.isLoaded, isFalse);
  });

  test('loadForTesting publishes items and marks the catalog loaded', () {
    ExerciseCatalogService.loadForTesting([
      (name: 'Barbell Row', category: 'Back'),
    ]);

    expect(ExerciseCatalogService.defaults.single.name, 'Barbell Row');
    expect(ExerciseCatalogService.isLoaded, isTrue);
  });

  test('an empty catalog still counts as loaded', () {
    ExerciseCatalogService.loadForTesting(const []);

    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(
      ExerciseCatalogService.isLoaded,
      isTrue,
      reason: 'empty-but-present must be distinct from fetch failure',
    );
  });

  test('reset returns the service to the not-loaded state', () {
    ExerciseCatalogService.loadForTesting([
      (name: 'Barbell Row', category: 'Back'),
    ]);
    ExerciseCatalogService.resetForTesting();

    expect(ExerciseCatalogService.defaults, isEmpty);
    expect(ExerciseCatalogService.isLoaded, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vivordo_health && flutter test test/exercise_catalog_service_test.dart
```

Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `vivordo_health/lib/src/services/exercise_catalog_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/exercise_catalog.dart';

export '../utils/exercise_catalog.dart';

/// The default exercise list, served from Firestore so it can change without
/// an app release.
///
/// Firestore's disk cache (enabled by default, never cleared by this app)
/// serves the document offline, so a user who has fetched it once keeps it.
/// [prefetch] therefore runs at sign-in rather than when the picker opens.
class ExerciseCatalogService {
  ExerciseCatalogService._();

  static const _collection = 'exercise_catalog';
  static const _document = 'current';

  static List<WorkoutExerciseCatalogItem> _defaults = const [];
  static bool _isLoaded = false;

  /// The default exercises, in catalog order. Empty until [prefetch] succeeds.
  static List<WorkoutExerciseCatalogItem> get defaults => _defaults;

  /// Whether the catalog document was actually read.
  ///
  /// Distinct from `defaults.isEmpty`: a fetch failure and a genuinely empty
  /// catalog both leave [defaults] empty, but only the latter is loaded.
  /// Anything that writes to user data based on "not in the catalog" must
  /// check this first.
  static bool get isLoaded => _isLoaded;

  /// Reads the catalog once. Safe to call repeatedly; never throws.
  static Future<void> prefetch() async {
    if (_isLoaded) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(_document)
          .get();
      if (!snapshot.exists) return;
      _defaults = parseExerciseCatalog(snapshot.data());
      _isLoaded = true;
    } on FirebaseException catch (error) {
      // Offline with a cold cache, or rules not yet deployed. The picker shows
      // no defaults and the history back-fill stays disabled until a later
      // launch succeeds.
      debugPrint('Exercise catalog fetch failed: ${error.code}');
    }
  }

  @visibleForTesting
  static void loadForTesting(List<WorkoutExerciseCatalogItem> items) {
    _defaults = List.unmodifiable(items);
    _isLoaded = true;
  }

  @visibleForTesting
  static void resetForTesting() {
    _defaults = const [];
    _isLoaded = false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vivordo_health && flutter test test/exercise_catalog_service_test.dart
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd vivordo_health
dart format lib/src/services/exercise_catalog_service.dart test/exercise_catalog_service_test.dart
flutter analyze 2>&1 | grep -c "error •"   # expect 0
cd .. && git add vivordo_health/lib/src/services/exercise_catalog_service.dart vivordo_health/test/exercise_catalog_service_test.dart
git commit -m "Add exercise catalog service"
```

---

### Task 3: Back-fill guard

The highest-risk change in this plan. `_loadCustomExercises` recovers exercises from workout history, treats anything absent from the default library as user-created, and **writes it into `users/{uid}/custom_exercises`**. Once defaults are remote, a failed fetch makes every default in a user's history look user-created, and the back-fill would permanently write hundreds of defaults into that user's collection.

**Files:**
- Create: `vivordo_health/lib/src/utils/custom_exercise_backfill.dart`
- Test: `vivordo_health/test/custom_exercise_backfill_test.dart`

**Interfaces:**
- Consumes: `WorkoutExerciseCatalogItem`, `exerciseNameKey` from Task 1.
- Produces: `List<WorkoutExerciseCatalogItem> customExerciseAdditions({required bool catalogLoaded, required Iterable<WorkoutExerciseCatalogItem> catalog, required Iterable<WorkoutExerciseCatalogItem> known, required Iterable<WorkoutExerciseCatalogItem> recovered})`.

- [ ] **Step 1: Write the failing test**

Create `vivordo_health/test/custom_exercise_backfill_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/custom_exercise_backfill.dart';

void main() {
  const catalog = <WorkoutExerciseCatalogItem>[
    (name: 'Barbell Bench Press', category: 'Chest'),
    (name: 'Barbell Row', category: 'Back'),
  ];

  test('returns nothing when the catalog failed to load', () {
    final additions = customExerciseAdditions(
      catalogLoaded: false,
      catalog: const [],
      known: const [],
      recovered: const [
        (name: 'Barbell Bench Press', category: 'Chest'),
        (name: 'Barbell Row', category: 'Back'),
      ],
    );

    expect(
      additions,
      isEmpty,
      reason: 'a cold catalog must never relabel defaults as user-created',
    );
  });

  test('keeps history entries that are genuinely not in the catalog', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [
        (name: 'Barbell Row', category: 'Back'),
        (name: 'Sled Push', category: 'Legs'),
      ],
    );

    expect(additions.map((e) => e.name), ['Sled Push']);
  });

  test('an empty but loaded catalog still allows additions', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: const [],
      known: const [],
      recovered: const [(name: 'Sled Push', category: 'Legs')],
    );

    expect(additions.map((e) => e.name), ['Sled Push']);
  });

  test('ignores entries already known as custom', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [(name: 'Sled Push', category: 'Legs')],
      recovered: const [(name: 'Sled Push', category: 'Legs')],
    );

    expect(additions, isEmpty);
  });

  test('matches the catalog ignoring case and punctuation', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [(name: 'barbell-bench  press', category: 'Chest')],
    );

    expect(additions, isEmpty);
  });

  test('de-duplicates repeats within the recovered list', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [
        (name: 'Sled Push', category: 'Legs'),
        (name: 'Sled Push', category: 'Legs'),
      ],
    );

    expect(additions, hasLength(1));
  });

  test('drops entries whose name has no usable characters', () {
    final additions = customExerciseAdditions(
      catalogLoaded: true,
      catalog: catalog,
      known: const [],
      recovered: const [(name: '!!!', category: 'Legs')],
    );

    expect(additions, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vivordo_health && flutter test test/custom_exercise_backfill_test.dart
```

Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `vivordo_health/lib/src/utils/custom_exercise_backfill.dart`:

```dart
import 'exercise_catalog.dart';

export 'exercise_catalog.dart' show WorkoutExerciseCatalogItem;

/// Exercises recovered from workout history that should be saved as the user's
/// own custom exercises.
///
/// Returns nothing unless [catalogLoaded] is true. The caller writes these into
/// `users/{uid}/custom_exercises`, so running against a catalog that failed to
/// load would permanently relabel that user's default exercises as
/// user-created. An empty catalog that did load is a legitimate state and does
/// not block the back-fill.
List<WorkoutExerciseCatalogItem> customExerciseAdditions({
  required bool catalogLoaded,
  required Iterable<WorkoutExerciseCatalogItem> catalog,
  required Iterable<WorkoutExerciseCatalogItem> known,
  required Iterable<WorkoutExerciseCatalogItem> recovered,
}) {
  if (!catalogLoaded) return const [];

  final seen = <String>{
    for (final exercise in catalog) exerciseNameKey(exercise.name),
    for (final exercise in known) exerciseNameKey(exercise.name),
  };

  final additions = <WorkoutExerciseCatalogItem>[];
  for (final exercise in recovered) {
    final key = exerciseNameKey(exercise.name);
    if (key.isEmpty) continue;
    if (seen.add(key)) additions.add(exercise);
  }
  return List.unmodifiable(additions);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vivordo_health && flutter test test/custom_exercise_backfill_test.dart
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Format, analyze, commit**

```bash
cd vivordo_health
dart format lib/src/utils/custom_exercise_backfill.dart test/custom_exercise_backfill_test.dart
flutter analyze 2>&1 | grep -c "error •"   # expect 0
cd .. && git add vivordo_health/lib/src/utils/custom_exercise_backfill.dart vivordo_health/test/custom_exercise_backfill_test.dart
git commit -m "Guard the custom exercise back-fill on a loaded catalog"
```

---

### Task 4: Seed data, seed script, and Firestore rule

Produces everything that has to exist in Firebase before the app change ships.

**Files:**
- Create: `vivordo_health/functions/exercise_catalog.js`
- Create: `vivordo_health/functions/scripts/seed_exercise_catalog.js`
- Create: `vivordo_health/functions/scripts/exercise_catalog_seed.json`
- Create: `vivordo_health/functions/test/exercise_catalog.test.js`
- Modify: `vivordo_health/firestore.rules`

**Interfaces:**
- Consumes: the `const _exerciseLibrary` block in `vivordo_health/lib/screens/fitness_screen.dart:3167-5854` as extraction input. That block is deleted in Task 5, so this task must run first.
- Produces: `exercise_catalog/current` in Firestore; `buildCatalogDocument(entries, version)` exported from `functions/exercise_catalog.js`.

- [ ] **Step 1: Extract the seed JSON from the Dart source**

Run from the repository root. This parses the existing const block; it does not edit it.

```bash
python3 - <<'PY'
import re, json
src = open('vivordo_health/lib/screens/fitness_screen.dart').read()
start = src.index('const _exerciseLibrary = <_ExerciseDefinition>[')
end = src.index('\n];\n', start)
block = src[start:end]

entries = re.findall(
    r"_ExerciseDefinition\(\s*name:\s*'((?:[^'\\]|\\.)*)'\s*,"
    r"\s*category:\s*'((?:[^'\\]|\\.)*)'\s*,?\s*\)",
    block)

assert len(entries) == 1128, f'expected 1128 entries, parsed {len(entries)}'
assert block.count('_ExerciseDefinition(') == len(entries), 'regex missed entries'

out = [{'n': n.replace("\\'", "'"), 'c': c} for n, c in entries]
json.dump(out, open('vivordo_health/functions/scripts/exercise_catalog_seed.json', 'w'),
          indent=2, ensure_ascii=False)
print('wrote', len(out), 'entries')
PY
```

Expected: `wrote 1128 entries`. Both asserts must pass; if either fails, stop and inspect rather than lowering the count.

- [ ] **Step 2: Write the failing test**

Create `vivordo_health/functions/test/exercise_catalog.test.js`:

```javascript
"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {buildCatalogDocument} = require("../exercise_catalog");
const seed = require("../scripts/exercise_catalog_seed.json");

test("wraps entries in a versioned document", () => {
  const doc = buildCatalogDocument(
      [{n: "Barbell Row", c: "Back"}],
      4,
  );

  assert.equal(doc.version, 4);
  assert.deepEqual(doc.exercises, [{n: "Barbell Row", c: "Back"}]);
});

test("preserves entry order", () => {
  const doc = buildCatalogDocument(
      [{n: "A", c: "Chest"}, {n: "B", c: "Back"}, {n: "C", c: "Legs"}],
      1,
  );

  assert.deepEqual(doc.exercises.map((e) => e.n), ["A", "B", "C"]);
});

test("rejects an entry with no name", () => {
  assert.throws(
      () => buildCatalogDocument([{n: "  ", c: "Chest"}], 1),
      /name/,
  );
});

test("defaults a missing category to Other", () => {
  const doc = buildCatalogDocument([{n: "Sled Push"}], 1);

  assert.equal(doc.exercises[0].c, "Other");
});

test("the committed seed has 1128 uniquely named entries", () => {
  assert.equal(seed.length, 1128);
  assert.equal(new Set(seed.map((e) => e.n)).size, 1128);
});

test("the committed seed builds a document under the 1MB limit", () => {
  const doc = buildCatalogDocument(seed, 1);

  assert.equal(doc.exercises.length, 1128);
  assert.ok(
      Buffer.byteLength(JSON.stringify(doc)) < 1024 * 1024,
      "catalog document must fit in one Firestore document",
  );
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd vivordo_health/functions && node --test test/exercise_catalog.test.js
```

Expected: FAIL — `Cannot find module '../exercise_catalog'`.

- [ ] **Step 4: Write minimal implementation**

Create `vivordo_health/functions/exercise_catalog.js`:

```javascript
"use strict";

/**
 * Builds the `exercise_catalog/current` document body.
 *
 * Entry order is preserved: the Circle challenge picker renders the catalog
 * unsorted, so the stored order is what users see.
 *
 * @param {Array<{n: string, c: string}>} entries Exercises, in display order.
 * @param {number} version Catalog version, bumped on every write.
 * @return {{version: number, exercises: Array<{n: string, c: string}>}} Body.
 */
function buildCatalogDocument(entries, version) {
  const exercises = entries.map((entry, index) => {
    const name = String(entry.n || "").trim();
    if (!name) {
      throw new Error(`entry ${index} has no name`);
    }
    const category = String(entry.c || "").trim();
    return {n: name, c: category || "Other"};
  });

  return {version, exercises};
}

module.exports = {buildCatalogDocument};
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd vivordo_health/functions && node --test test/exercise_catalog.test.js
```

Expected: PASS, 6 tests.

- [ ] **Step 6: Write the seed script**

Create `vivordo_health/functions/scripts/seed_exercise_catalog.js`:

```javascript
/* eslint-disable */
// =============================================================================
// Uploads the default exercise catalog to exercise_catalog/current.
//
// exercise_catalog_seed.json is the source of truth. This script overwrites the
// document, so any Firebase console edit that was not mirrored back into the
// JSON is reverted by the next run.
//
// SAFETY: dry-run by default — prints what it would write and writes nothing.
//         Pass --apply to actually write.
//
// RUN (from the functions/ directory):
//   1. Authenticate Application Default Credentials, either:
//        gcloud auth application-default login
//      or set a service-account key:
//        export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
//   2. Dry run:   node scripts/seed_exercise_catalog.js
//   3. Apply:     node scripts/seed_exercise_catalog.js --apply
// =============================================================================

const admin = require("firebase-admin");
const {buildCatalogDocument} = require("../exercise_catalog");
const entries = require("./exercise_catalog_seed.json");

admin.initializeApp({projectId: "vivordo-health"});
const db = admin.firestore();

const APPLY = process.argv.includes("--apply");
const REF = db.collection("exercise_catalog").doc("current");

async function main() {
  const existing = await REF.get();
  const version = existing.exists ? (existing.data().version || 0) + 1 : 1;
  const doc = buildCatalogDocument(entries, version);
  const bytes = Buffer.byteLength(JSON.stringify(doc));

  console.log(`entries : ${doc.exercises.length}`);
  console.log(`version : ${version}${existing.exists ? "" : " (new document)"}`);
  console.log(`size    : ${(bytes / 1024).toFixed(1)}KB of 1024KB`);

  if (!APPLY) {
    console.log("\nDry run. Re-run with --apply to write.");
    return;
  }

  await REF.set({
    ...doc,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("\nWrote exercise_catalog/current.");
}

main().then(() => process.exit(0)).catch((error) => {
  console.error(error);
  process.exit(1);
});
```

- [ ] **Step 7: Verify the seed script dry-runs**

```bash
cd vivordo_health/functions && node scripts/seed_exercise_catalog.js
```

Expected: prints `entries : 1128`, a version, a size near 57KB, then `Dry run.` If credentials are missing it exits non-zero on the `REF.get()` call — that is expected without ADC and does not block the rest of this task.

- [ ] **Step 8: Add the Firestore rule**

In `vivordo_health/firestore.rules`, insert this block immediately before the closing `bug_reports` block's trailing `}` of `match /databases/{database}/documents {` — that is, as a sibling of the other top-level `match` statements:

```
    // ── Default exercise catalog (seeded by functions/scripts) ──────────────
    // One document read by every signed-in client at sign-in. Writes come only
    // from the Admin SDK seed script, which bypasses these rules.
    match /exercise_catalog/{document} {
      allow read: if request.auth != null;
      allow write: if false;
    }
```

- [ ] **Step 9: Lint and commit**

```bash
cd vivordo_health && npm --prefix functions run lint
cd .. && git add vivordo_health/functions/exercise_catalog.js \
  vivordo_health/functions/scripts/seed_exercise_catalog.js \
  vivordo_health/functions/scripts/exercise_catalog_seed.json \
  vivordo_health/functions/test/exercise_catalog.test.js \
  vivordo_health/firestore.rules
git commit -m "Add exercise catalog seed data, seed script, and read rule"
```

---

### Task 5: Serve the picker from the catalog service

Deletes the 2,688-line const block and sources defaults from Task 2, adds the `isCustom` flag, and applies the Task 3 guard.

**Files:**
- Modify: `vivordo_health/lib/screens/fitness_screen.dart` (delete lines 3167-5854 and 5856-5866; edit `_ExerciseDefinition`, `_AddExerciseScreenState.initState`, `_loadCustomExercises`, `_createExercise`)

No test of its own: this task moves the data source without changing behaviour.
The guard it wires in is covered by Task 3, and the picker rules by Task 6.

**Interfaces:**
- Consumes: `ExerciseCatalogService`, `WorkoutExerciseCatalogItem` (Task 2); `customExerciseAdditions` (Task 3).
- Produces: `_ExerciseDefinition` gains `final bool isCustom`. `workoutExerciseCatalog` and `WorkoutExerciseCatalogItem` no longer exist in this file — Task 7 repoints `circle_screen`.

- [ ] **Step 1: Delete the const block and the derived catalog**

Run from the repository root:

```bash
python3 - <<'PY'
p = 'vivordo_health/lib/screens/fitness_screen.dart'
s = open(p).read()

start = s.index('const _exerciseLibrary = <_ExerciseDefinition>[')
end = s.index('\n];\n', start) + len('\n];\n')

tail = """typedef WorkoutExerciseCatalogItem = ({String name, String category});

/// Shared read-only view of the exercises offered by the Fitness workout
/// builder. Other screens should consume this instead of duplicating names.
final List<WorkoutExerciseCatalogItem> workoutExerciseCatalog =
    List.unmodifiable(
      _exerciseLibrary.map(
        (exercise) => (name: exercise.name, category: exercise.category),
      ),
    );

"""
assert tail in s[end:end + 700]

replacement = """List<WorkoutExerciseCatalogItem>? _librarySource;
List<_ExerciseDefinition>? _libraryCache;

/// The default exercises, mapped once per catalog load.
///
/// ExerciseCatalogService publishes one immutable list, so identity is a sound
/// cache key and the picker does not remap 1,128 entries on every build.
List<_ExerciseDefinition> get _exerciseLibrary {
  final source = ExerciseCatalogService.defaults;
  if (!identical(source, _librarySource)) {
    _librarySource = source;
    _libraryCache = source
        .map(
          (exercise) => _ExerciseDefinition(
            name: exercise.name,
            category: exercise.category,
          ),
        )
        .toList(growable: false);
  }
  return _libraryCache!;
}

"""

s = s[:start] + replacement + s[end:].replace(tail, '', 1)
s = s.replace(
    "import '../src/services/workout_service.dart';",
    "import '../src/services/exercise_catalog_service.dart';\n"
    "import '../src/services/workout_service.dart';",
    1)
open(p, 'w').write(s)
print('const block removed')
PY
```

- [ ] **Step 2: Add the isCustom flag**

In `vivordo_health/lib/screens/fitness_screen.dart`, replace the `_ExerciseDefinition` class:

```dart
class _ExerciseDefinition {
  const _ExerciseDefinition({
    required this.name,
    required this.category,
    this.isCustom = false,
  });

  final String name;
  final String category;

  /// True for exercises the user created, false for catalog defaults.
  /// Derived from the source the exercise was loaded from, never persisted on
  /// the workout record.
  final bool isCustom;
}
```

Then delete the now-duplicated helper immediately below it, since Task 1 provides it:

```dart
String _exerciseNameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
```

Replace every remaining call to `_exerciseNameKey(` in this file with `exerciseNameKey(`:

```bash
cd vivordo_health && sed -i 's/\b_exerciseNameKey(/exerciseNameKey(/g' lib/screens/fitness_screen.dart
```

- [ ] **Step 3: Mark loaded and created exercises as custom**

In `_AddExerciseScreenState.initState`, the entries carried in from a resumed workout that are not in the catalog are user-created:

```dart
    final libraryNames = _exerciseLibrary
        .map((exercise) => exerciseNameKey(exercise.name))
        .toSet();
    _customExercises.addAll(
      widget.initiallySelected
          .where(
            (exercise) => !libraryNames.contains(exerciseNameKey(exercise.name)),
          )
          .map(
            (exercise) => _ExerciseDefinition(
              name: exercise.name,
              category: exercise.category,
              isCustom: true,
            ),
          ),
    );
```

In `_createExercise`, the dialog's result becomes custom. Replace:

```dart
                  _ExerciseDefinition(name: name.trim(), category: category),
```

with:

```dart
                  _ExerciseDefinition(
                    name: name.trim(),
                    category: category,
                    isCustom: true,
                  ),
```

- [ ] **Step 4: Apply the back-fill guard**

Replace the whole body of `_loadCustomExercises` with:

```dart
  Future<void> _loadCustomExercises() async {
    final recovered = <WorkoutExerciseCatalogItem>[];
    try {
      final saved = await WorkoutService.loadCustomExercises();
      recovered.addAll(
        saved.map(
          (exercise) => (name: exercise.name, category: exercise.category),
        ),
      );
    } catch (_) {
      // Completed workout history below can still recover older exercises.
    }
    try {
      final workouts = await WorkoutService.loadRecent(limit: 100);
      recovered.addAll(
        workouts.expand(
          (workout) => workout.exercises.map(
            (exercise) => (name: exercise.name, category: exercise.category),
          ),
        ),
      );
    } catch (_) {
      // Keep the built-in and already loaded custom exercises available.
    }
    if (!mounted) return;

    final additions = customExerciseAdditions(
      catalogLoaded: ExerciseCatalogService.isLoaded,
      catalog: _exerciseLibrary.map(
        (exercise) => (name: exercise.name, category: exercise.category),
      ),
      known: _customExercises.map(
        (exercise) => (name: exercise.name, category: exercise.category),
      ),
      recovered: recovered,
    );
    if (additions.isEmpty) return;

    setState(
      () => _customExercises.addAll(
        additions.map(
          (exercise) => _ExerciseDefinition(
            name: exercise.name,
            category: exercise.category,
            isCustom: true,
          ),
        ),
      ),
    );
    for (final exercise in additions) {
      unawaited(
        WorkoutService.saveCustomExercise(
          name: exercise.name,
          category: exercise.category,
        ).catchError((_) {}),
      );
    }
  }
```

Add the import beside the service import added in Step 1:

```dart
import '../src/utils/custom_exercise_backfill.dart';
```

- [ ] **Step 5: Analyze and run the full suite**

```bash
export PATH="$HOME/source/flutter/bin:$PATH"
cd vivordo_health
flutter analyze 2>&1 | grep "error •"
```

Expected: `circle_screen.dart` reports undefined `WorkoutExerciseCatalogItem` and `workoutExerciseCatalog`. That is expected and is fixed in Task 7. Every other error must be zero. Do not commit with analyzer errors outside `circle_screen.dart`.

- [ ] **Step 6: Commit**

```bash
cd .. && git add vivordo_health/lib/screens/fitness_screen.dart
git commit -m "Serve default exercises from the catalog service"
```

---

### Task 6: Picker badge and pinned section

The search, filter, sort and partition rules carry real logic and are pulled
into a pure function so they can be tested. `_AddExerciseScreen` is private,
lives inside a 4,500-line screen, and needs Firebase initialised to reach, so
testing this through the widget would require a fake-Firestore dependency that
this plan does not add.

**Files:**
- Create: `vivordo_health/lib/src/utils/exercise_picker_results.dart`
- Create: `vivordo_health/test/exercise_picker_results_test.dart`
- Modify: `vivordo_health/lib/screens/fitness_screen.dart` (`_filteredExercises`, the list body, `_ExercisePickerRow`)

**Interfaces:**
- Consumes: `_ExerciseDefinition.isCustom` (Task 5).
- Produces: `typedef PickerExercise = ({String name, String category, bool isCustom});`, `ExercisePickerResults`, `ExercisePickerResults exercisePickerResults({required String search, required String filter, required Iterable<PickerExercise> catalog, required Iterable<PickerExercise> custom})`, and the private `_CustomExerciseBadge` widget.

- [ ] **Step 1: Write the failing test**

Create `vivordo_health/test/exercise_picker_results_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/exercise_picker_results.dart';

void main() {
  const catalog = <PickerExercise>[
    (name: 'Barbell Row', category: 'Back', isCustom: false),
    (name: 'Arnold Press', category: 'Shoulders', isCustom: false),
    (name: 'Cable Press', category: 'Chest', isCustom: false),
  ];
  const custom = <PickerExercise>[
    (name: 'Sled Push', category: 'Legs', isCustom: true),
    (name: 'Cable Y-Raise', category: 'Shoulders', isCustom: true),
  ];

  ExercisePickerResults results({String search = '', String filter = 'All'}) =>
      exercisePickerResults(
        search: search,
        filter: filter,
        catalog: catalog,
        custom: custom,
      );

  test('browsing splits custom into its own section', () {
    final result = results();

    expect(result.sectioned, isTrue);
    expect(result.custom.map((e) => e.name), ['Cable Y-Raise', 'Sled Push']);
    expect(result.defaults.map((e) => e.name), [
      'Arnold Press',
      'Barbell Row',
      'Cable Press',
    ]);
  });

  test('a search collapses to one merged, sorted list', () {
    final result = results(search: 'cable');

    expect(result.sectioned, isFalse);
    expect(result.custom, isEmpty);
    expect(result.defaults.map((e) => e.name), ['Cable Press', 'Cable Y-Raise']);
  });

  test('custom entries keep their flag inside a merged list', () {
    final result = results(search: 'cable');

    final yRaise = result.defaults.firstWhere((e) => e.name == 'Cable Y-Raise');
    final press = result.defaults.firstWhere((e) => e.name == 'Cable Press');
    expect(yRaise.isCustom, isTrue);
    expect(press.isCustom, isFalse);
  });

  test('a category filter collapses sections and filters both sources', () {
    final result = results(filter: 'Shoulders');

    expect(result.sectioned, isFalse);
    expect(result.defaults.map((e) => e.name), [
      'Arnold Press',
      'Cable Y-Raise',
    ]);
  });

  test('search matches category as well as name', () {
    final result = results(search: 'legs');

    expect(result.defaults.map((e) => e.name), ['Sled Push']);
  });

  test('search ignores case and surrounding whitespace', () {
    expect(results(search: '  ROW  ').defaults.map((e) => e.name), [
      'Barbell Row',
    ]);
  });

  test('whitespace-only search still counts as browsing', () {
    expect(results(search: '   ').sectioned, isTrue);
  });

  test('no custom exercises yields an empty custom section', () {
    final result = exercisePickerResults(
      search: '',
      filter: 'All',
      catalog: catalog,
      custom: const [],
    );

    expect(result.sectioned, isTrue);
    expect(result.custom, isEmpty);
    expect(result.defaults, hasLength(3));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="$HOME/source/flutter/bin:$PATH"
cd vivordo_health && flutter test test/exercise_picker_results_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '.../exercise_picker_results.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `vivordo_health/lib/src/utils/exercise_picker_results.dart`:

```dart
/// One row in the Add Exercise picker.
typedef PickerExercise = ({String name, String category, bool isCustom});

/// What the picker should render for the current search and filter.
///
/// When [sectioned] is true, [custom] is shown under its own heading above
/// [defaults]. Otherwise [custom] is empty and [defaults] holds every match in
/// one ranking, each still carrying its own `isCustom` flag.
class ExercisePickerResults {
  const ExercisePickerResults({
    required this.sectioned,
    required this.custom,
    required this.defaults,
  });

  final bool sectioned;
  final List<PickerExercise> custom;
  final List<PickerExercise> defaults;
}

List<PickerExercise> _matching(
  Iterable<PickerExercise> source,
  String query,
  String filter,
) =>
    source.where((exercise) {
        final matchesFilter = filter == 'All' || exercise.category == filter;
        final matchesSearch =
            query.isEmpty ||
            exercise.name.toLowerCase().contains(query) ||
            exercise.category.toLowerCase().contains(query);
        return matchesFilter && matchesSearch;
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Splits the picker into a pinned custom section plus the defaults while
/// browsing, and into one merged list once a search or category filter is
/// narrowing things down — a user who typed a query wants one ranking, not
/// their match split across two headings.
ExercisePickerResults exercisePickerResults({
  required String search,
  required String filter,
  required Iterable<PickerExercise> catalog,
  required Iterable<PickerExercise> custom,
}) {
  final query = search.trim().toLowerCase();
  final sectioned = query.isEmpty && filter == 'All';

  if (!sectioned) {
    return ExercisePickerResults(
      sectioned: false,
      custom: const [],
      defaults: _matching([...catalog, ...custom], query, filter),
    );
  }

  return ExercisePickerResults(
    sectioned: true,
    custom: _matching(custom, query, filter),
    defaults: _matching(catalog, query, filter),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vivordo_health && flutter test test/exercise_picker_results_test.dart
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Add the badge widget**

Append to `vivordo_health/lib/screens/fitness_screen.dart`:

```dart
class _CustomExerciseBadge extends StatelessWidget {
  const _CustomExerciseBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _purple.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'CUSTOM',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: .8,
        color: _purple,
      ),
    ),
  );
}
```

- [ ] **Step 6: Render the badge in the row**

In `_ExercisePickerRow.build`, replace the category `Text` with a row carrying the badge:

```dart
                  Row(
                    children: [
                      Text(
                        exercise.category,
                        style: const TextStyle(color: _muted),
                      ),
                      if (exercise.isCustom) ...[
                        const SizedBox(width: 8),
                        const _CustomExerciseBadge(),
                      ],
                    ],
                  ),
```

- [ ] **Step 7: Drive the picker from the shared function**

Add the import beside the other util imports in `fitness_screen.dart`:

```dart
import '../src/utils/exercise_picker_results.dart';
```

Replace the `_filteredExercises` getter with an adapter over the new function:

```dart
  PickerExercise _entry(_ExerciseDefinition exercise) => (
    name: exercise.name,
    category: exercise.category,
    isCustom: exercise.isCustom,
  );

  _ExerciseDefinition _definitionFor(PickerExercise entry) =>
      _ExerciseDefinition(
        name: entry.name,
        category: entry.category,
        isCustom: entry.isCustom,
      );

  ExercisePickerResults get _pickerResults => exercisePickerResults(
    search: _search,
    filter: _filter,
    catalog: _exerciseLibrary.map(_entry),
    custom: _customExercises.map(_entry),
  );
```

- [ ] **Step 8: Render the pinned section**

In `build`, replace `final exercises = _filteredExercises;` with:

```dart
    final results = _pickerResults;
    final customResults = results.custom.map(_definitionFor).toList();
    final exercises = results.defaults.map(_definitionFor).toList();
```

Then, inside the `Expanded > Column` that currently starts with the `ALL EXERCISES` title, insert above that title:

```dart
                  if (customResults.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: _PickerSectionTitle('YOUR EXERCISES'),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: context.vivordoColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: context.vivordoColors.border),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: customResults.length,
                        itemBuilder: (context, index) {
                          final exercise = customResults[index];
                          return _ExercisePickerRow(
                            exercise: exercise,
                            selected: _selected.contains(exercise.name),
                            onTap: () => _toggle(exercise),
                          );
                        },
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 72),
                      ),
                    ),
                  ],
```

- [ ] **Step 9: Analyze and run the suite**

```bash
export PATH="$HOME/source/flutter/bin:$PATH"
cd vivordo_health
flutter analyze 2>&1 | grep "error •"
```

Expected: only the two `circle_screen.dart` errors left over from Task 5, fixed in Task 7. Any other error must be resolved before committing.

- [ ] **Step 10: Commit**

Do not run `dart format` on `fitness_screen.dart` — it is already format-dirty on `robs_testing`, and formatting it would bury this change in an unrelated whole-file diff. Format only the new files.

```bash
cd vivordo_health
dart format lib/src/utils/exercise_picker_results.dart test/exercise_picker_results_test.dart
cd .. && git add vivordo_health/lib/src/utils/exercise_picker_results.dart   vivordo_health/test/exercise_picker_results_test.dart   vivordo_health/lib/screens/fitness_screen.dart
git commit -m "Mark user-created exercises in the picker"
```

---

### Task 7: Wire the prefetch and repoint Circle

Closes the analyzer errors Task 5 left open and makes the catalog actually load at runtime.

**Files:**
- Modify: `vivordo_health/lib/screens/circle_screen.dart:17-21` (the `show` import from `fitness_screen.dart`)
- Modify: `vivordo_health/lib/main.dart` (`_AuthGateState._triggerFullSync`)

**Interfaces:**
- Consumes: `ExerciseCatalogService.prefetch()`, `ExerciseCatalogService.defaults`, `WorkoutExerciseCatalogItem` (Task 2).
- Produces: nothing downstream.

- [ ] **Step 1: Repoint circle_screen at the service**

`circle_screen.dart` imports both the typedef and the catalog from `fitness_screen.dart`. Replace that import:

```dart
import 'fitness_screen.dart'
    show
        ActivityRingsPainter,
        WorkoutExerciseCatalogItem,
        workoutExerciseCatalog;
```

with:

```dart
import 'fitness_screen.dart' show ActivityRingsPainter;
```

and add, in the `package:` import block so it sorts before `theme/vivordo_theme.dart`:

```dart
import 'package:vivordo_health/src/services/exercise_catalog_service.dart';
```

`ActivityRingsPainter` still comes from `fitness_screen.dart` and must stay.

- [ ] **Step 2: Point the two catalog reads at the service**

In `_availableSpecificExercises`, replace both references to `workoutExerciseCatalog` with `ExerciseCatalogService.defaults`:

```dart
  List<WorkoutExerciseCatalogItem> get _availableSpecificExercises {
    if (_definition.kind == _CustomChallengeCount.activity) {
      return ExerciseCatalogService.defaults
          .where(
            (exercise) =>
                exercise.category == 'Cardio' || exercise.category == 'Sports',
          )
          .toList(growable: false);
    }
    return ExerciseCatalogService.defaults;
  }
```

- [ ] **Step 3: Prefetch after sign-in**

In `vivordo_health/lib/main.dart`, add the import beside the other service imports:

```dart
import 'package:vivordo_health/src/services/exercise_catalog_service.dart';
```

In `_AuthGateState._triggerFullSync`, add the prefetch beside the other once-per-login calls:

```dart
    NotificationService().configureForUser(uid);
    unawaited(ExerciseCatalogService.prefetch());
    unawaited(HomeWidgetService.refreshCalendarSnapshot(force: true));
    AnalyticsService().logLogin();
```

`prefetch` never throws and returns early once loaded, so it is safe to fire unawaited on every login.

- [ ] **Step 4: Verify the whole suite against baseline**

```bash
export PATH="$HOME/source/flutter/bin:$PATH"
cd vivordo_health
flutter analyze 2>&1 | grep -oP "^\s*(error|warning|info) " | sort | uniq -c
flutter test 2>&1 | tail -2
```

Expected: 0 errors, and warning/info counts no higher than the 28/188 baseline.

`flutter test` must report **210 passing**: the 186 baseline plus 24 new Dart
tests (5 from Task 1, 4 from Task 2, 7 from Task 3, 8 from Task 6).

```bash
cd functions && node --test test/*.test.js 2>&1 | tail -3
```

Expected: all Node tests pass, including the 6 added in Task 4.

- [ ] **Step 5: Commit**

```bash
cd vivordo_health && dart format lib/main.dart
cd .. && git add vivordo_health/lib/screens/circle_screen.dart vivordo_health/lib/main.dart
git commit -m "Prefetch the exercise catalog and source Circle from it"
```

---

## Deployment

These steps are not part of any commit and must happen against the live project. The full detail is in the spec's "Firebase-side changes" section.

- [ ] Deploy the rule: `cd vivordo_health && firebase deploy --only firestore:rules --project vivordo-health`
- [ ] Authenticate: `gcloud auth application-default login`
- [ ] Dry run: `cd vivordo_health/functions && node scripts/seed_exercise_catalog.js`
- [ ] Apply: `node scripts/seed_exercise_catalog.js --apply`
- [ ] Verify in Firebase console that `exercise_catalog/current` exists and `exercises` has 1,128 entries.

**Both the rule and the seed must be live before the app build reaches users.** A client that can read nothing shows an empty exercise picker.
