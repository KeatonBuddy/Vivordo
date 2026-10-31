import Foundation
import WatchConnectivity

/// What the watch did, on its way to the phone: a finished reset, an energy
/// check-in, a priority ticked off. Kept in the app group and sent as the
/// watch's application context, the last day's worth, so one done while the
/// phone was away still arrives; the phone (WatchSnapshotBridge) queues only
/// those it hasn't seen and Flutter saves them.
enum WatchActions {
  static func send(_ kind: String, _ fields: [String: Any] = [:]) {
    let nowMs = Date().timeIntervalSince1970 * 1000
    var action = fields
    action["kind"] = kind
    // Int64, not Int: on an arm64_32 watch (SE, Series 4-6) Int is 32 bits
    // and a millisecond timestamp traps.
    action["at"] = Int64(nowMs)
    let defaults = UserDefaults(suiteName: WatchSnapshot.appGroup)
    var recent = (defaults?.array(forKey: "watchActions") as? [[String: Any]] ?? [])
      .filter { (($0["at"] as? NSNumber)?.doubleValue ?? 0) > nowMs - 86_400_000 }
    recent.append(action)
    defaults?.set(recent, forKey: "watchActions")
    do {
      try WCSession.default.updateApplicationContext(["watchActions": recent])
    } catch {
      NSLog("Vivordo watch: could not send \(kind): \(error)")
    }
  }

  /// Priorities ticked here that the phone has not confirmed yet, so the
  /// list shows them done straight away.
  static var tickedIds: Set<String> {
    get {
      Set(UserDefaults(suiteName: WatchSnapshot.appGroup)?.stringArray(forKey: "watchTicked") ?? [])
    }
    set {
      UserDefaults(suiteName: WatchSnapshot.appGroup)?.set(Array(newValue), forKey: "watchTicked")
    }
  }
}
