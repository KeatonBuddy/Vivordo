import Combine
import Foundation
import WatchConnectivity
import WidgetKit

/// Receives the phone's snapshot (WatchSnapshotBridge on the phone) and keeps
/// it in the watch's app group, where the app and the complications read it.
final class WatchSnapshotStore: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = WatchSnapshotStore()

  @Published private(set) var snapshot: WatchSnapshot?

  private override init() {
    snapshot = WatchSnapshot.load()
    super.init()
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  /// Re-reads the app group, for a new day or a return to the foreground.
  func refresh() {
    snapshot = WatchSnapshot.load()
    ResetScheduler.shared.schedule(for: snapshot)
  }

  // MARK: WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    // The system keeps the last context the phone sent, even across launches.
    if activationState == .activated, !session.receivedApplicationContext.isEmpty {
      store(session.receivedApplicationContext)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    store(context)
  }

  private func store(_ context: [String: Any]) {
    guard let defaults = UserDefaults(suiteName: WatchSnapshot.appGroup) else { return }
    for (key, value) in context { defaults.set(value, forKey: key) }
    WidgetCenter.shared.reloadAllTimelines()
    DispatchQueue.main.async { self.refresh() }
  }
}
