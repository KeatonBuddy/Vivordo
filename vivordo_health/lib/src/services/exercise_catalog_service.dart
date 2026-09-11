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
