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
      applySnapshot(exists: snapshot.exists, data: snapshot.data());
    } catch (error) {
      // Broad catch is intentional: this is a fire-and-forget boundary (called
      // unawaited from sign-in). Firestore.get() can throw FirebaseException,
      // PlatformException, or StateError if not initialized. All failures have
      // the same correct outcome: no defaults loaded, isLoaded stays false.
      // Catching Object prevents unhandled async errors in production.
      if (error is FirebaseException) {
        debugPrint('Exercise catalog fetch failed: ${error.code}');
      } else {
        debugPrint('Exercise catalog fetch failed: $error');
      }
    }
  }

  /// Applies a Firestore snapshot to the service state.
  ///
  /// Exposed for testing the state machine without a fake Firestore.
  /// Missing documents do not change state; present documents are parsed
  /// and marked loaded regardless of content (empty or garbage both count as loaded).
  @visibleForTesting
  static void applySnapshot({
    required bool exists,
    required Map<String, dynamic>? data,
  }) {
    if (!exists) return;
    _defaults = parseExerciseCatalog(data);
    _isLoaded = true;
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
