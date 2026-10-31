import Foundation
import WatchConnectivity

/// Mirrors the app-group snapshot the phone already writes for Siri and the
/// home-screen widgets (AppDelegate `updateSnapshot`) to the paired watch.
///
/// App Groups don't cross devices, so the watch keeps the same keys in its own
/// app group (see VivordoWatch/WatchSnapshotStore.swift). The watch app and its
/// complications then read exactly what the phone showed, with no second
/// schema to keep in step.
final class WatchSnapshotBridge: NSObject, WCSessionDelegate {
  static let shared = WatchSnapshotBridge()

  /// Keys copied to the watch. Everything here is already a property-list
  /// value in the app group (numbers, strings, arrays of those).
  static let keys: [String] = [
    "updatedAt", "dashboardName", "dashboardMetricsDay",
    // Capacity
    "dashboardHasCapacity", "capacityScore", "capacityDelta", "capacityLabel",
    "capacityNote", "capacityDay",
    // Demand
    "siriDemand", "siriDemandHeadline", "siriDemandAt",
    // Stress
    "dashboardHasStress", "stressScore", "siriStressScore", "stressUpdatedAt",
    "stressDrivers",
    // Heart, sleep, fitness
    "siriHeartRateLatest", "heartRateLatestAt", "siriHeartRateAverage",
    "siriHeartRateMinimum", "siriHeartRateMaximum",
    "siriSleepHours", "siriSleepNeed", "sleepUpdatedAt", "sleepStages",
    "steps", "stepsGoal", "activeCalories", "activeCaloriesGoal",
    "exerciseMinutes", "exerciseGoal",
    "siriTrainingState", "siriTrainingRatio", "siriTrainingHardDays",
    // Calendar
    "siriCalendarEvents", "calendarEvents", "calendarWeekUpdatedAt",
    "siriMeetingPatterns",
  ]

  /// Called on the main queue once a reset from the watch has been queued.
  var onReset: (() -> Void)?

  private override init() { super.init() }

  func activate() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Sends the current snapshot. Safe to call on every write: WatchConnectivity
  /// keeps only the latest context and drops one identical to the last.
  func push() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated,
          session.isPaired, session.isWatchAppInstalled,
          let defaults = UserDefaults(suiteName: "group.com.vivordo.health")
    else { return }
    var context: [String: Any] = [:]
    for key in Self.keys {
      if let value = defaults.object(forKey: key) { context[key] = value }
    }
    guard !context.isEmpty else { return }
    do {
      try session.updateApplicationContext(context)
    } catch {
      NSLog("Vivordo watch: could not send the snapshot: \(error)")
    }
  }

  // MARK: WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    guard activationState == .activated else { return }
    push()
    // Anything the watch sent while the phone app was away.
    queueResets(session.receivedApplicationContext["watchResets"] as? [[String: Any]] ?? [])
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionDidDeactivate(_ session: WCSession) {
    // The paired watch changed; activate again for the new one.
    session.activate()
  }

  func sessionWatchStateDidChange(_ session: WCSession) {
    push()
  }

  /// Resets finished on the watch (VivordoWatch/ResetView.swift), sent as
  /// the watch's application context. Each new one is queued under its own
  /// key, like Mood widget taps, until Flutter saves it (`pendingWatchResets`).
  func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    queueResets(context["watchResets"] as? [[String: Any]] ?? [])
  }

  private func queueResets(_ resets: [[String: Any]]) {
    guard !resets.isEmpty,
          let defaults = UserDefaults(suiteName: "group.com.vivordo.health") else { return }
    let seen = defaults.double(forKey: "watchResetsSeenAt")
    var latest = seen
    for var reset in resets {
      guard let at = (reset["at"] as? NSNumber)?.doubleValue, at > seen else { continue }
      reset["account"] = defaults.string(forKey: "moodAccount")
      defaults.set(reset, forKey: "pendingReset.\(Int64(at))")
      latest = max(latest, at)
    }
    guard latest > seen else { return }
    defaults.set(latest, forKey: "watchResetsSeenAt")
    DispatchQueue.main.async { self.onReset?() }
  }
}
