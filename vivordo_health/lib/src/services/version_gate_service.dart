import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class VersionCheckResult {
  final bool updateRequired;
  final String updateUrl;
  const VersionCheckResult({
    required this.updateRequired,
    required this.updateUrl,
  });
}

/// Gates app access on a minimum supported version, controlled remotely via
/// Firebase Remote Config so a forced update can be pushed without a new
/// release. Configure in Firebase Console → Remote Config:
///   minimum_supported_version — e.g. "1.2.0", the lowest version still allowed to run
///   update_url                — where "Update Now" sends the user (store listing, landing page, etc.)
class VersionGateService {
  static const _minVersionKey = 'minimum_supported_version';
  static const _updateUrlKey = 'update_url';

  static const _notRequired = VersionCheckResult(
    updateRequired: false,
    updateUrl: '',
  );

  /// Emits a result from the config already on the device straight away,
  /// then again once a fresh fetch lands, so the check never holds up
  /// launch. An outdated app can run for the few seconds the fetch takes
  /// before the gate closes.
  static Stream<VersionCheckResult> watch() async* {
    final String version;
    final FirebaseRemoteConfig rc;
    try {
      version = (await PackageInfo.fromPlatform()).version;
      rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      // Safe defaults: if Remote Config is unreachable (offline first
      // launch, outage), the minimum defaults to the running app's own
      // version — never "outdated" relative to itself — so a config
      // problem can't accidentally lock everyone out.
      await rc.setDefaults({_minVersionKey: version, _updateUrlKey: ''});
      // Applies the last fetched config, if a fetch landed after the
      // previous launch's activate.
      await rc.activate();
    } catch (_) {
      // Remote Config unusable — never block on a check that couldn't run.
      yield _notRequired;
      return;
    }
    yield _result(rc, version);
    try {
      await rc.fetchAndActivate();
      yield _result(rc, version);
    } catch (_) {
      // Unreachable: keep the answer from the config on the device.
    }
  }

  static VersionCheckResult _result(FirebaseRemoteConfig rc, String version) {
    final minVersion = rc.getString(_minVersionKey);
    return VersionCheckResult(
      updateRequired:
          minVersion.isNotEmpty && _compareVersions(version, minVersion) < 0,
      updateUrl: rc.getString(_updateUrlKey),
    );
  }

  /// Compares dotted numeric version strings (e.g. "1.9.0" vs "1.10.0" —
  /// this treats "10" as greater than "9", unlike a plain string compare).
  /// Negative if [a] < [b], zero if equal, positive if [a] > [b].
  static int _compareVersions(String a, String b) {
    final partsA = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final partsB = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = partsA.length > partsB.length
        ? partsA.length
        : partsB.length;
    for (var i = 0; i < length; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }
}
