import Combine
import Foundation
import UserNotifications

/// Two or more meetings in a row (each starting within `MeetingRuns.gap` of
/// the previous one ending) and the meeting that follows the run, if any.
struct MeetingRun: Equatable {
  let count: Int
  let start: Date
  let end: Date
  let next: WatchSnapshot.Event?
}

enum MeetingRuns {
  static let gap: TimeInterval = 5 * 60

  /// Runs that have not ended yet, earliest first.
  static func find(in events: [WatchSnapshot.Event], now: Date) -> [MeetingRun] {
    let sorted = events.sorted { $0.start < $1.start }
    var runs: [MeetingRun] = []
    var i = 0
    while i < sorted.count {
      var end = sorted[i].end
      var j = i
      while j + 1 < sorted.count, sorted[j + 1].start.timeIntervalSince(end) <= gap {
        j += 1
        end = max(end, sorted[j].end)
      }
      if j > i, end > now {
        runs.append(MeetingRun(
          count: j - i + 1, start: sorted[i].start, end: end,
          next: j + 1 < sorted.count ? sorted[j + 1] : nil))
      }
      i = j + 1
    }
    return runs
  }

  static func body(for run: MeetingRun) -> String {
    let since = run.start.formatted(date: .omitted, time: .shortened)
    let count = "\(spelled(run.count)) meetings in a row since \(since)."
    guard let next = run.next else { return "\(count) Take a minute to reset?" }
    let at = next.start.formatted(date: .omitted, time: .shortened)
    return "\(count) Take a minute to reset before \(next.title) at \(at)?"
  }

  private static func spelled(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .spellOut
    return (f.string(from: NSNumber(value: n)) ?? "\(n)").capitalized
  }
}

/// Keeps one local notification per upcoming run of back-to-backs, fired when
/// the run ends, and opens the reset when it is tapped.
final class ResetScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  static let shared = ResetScheduler()
  static let category = "VIVORDO_RESET"

  /// True while the reset screen should be up (notification tap or button).
  @Published var resetRequested = false

  private let center = UNUserNotificationCenter.current()

  func start() {
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: []),
    ])
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  /// Replaces every pending reset with one per run in the snapshot.
  func schedule(for snapshot: WatchSnapshot?, now: Date = Date()) {
    let runs = Array(MeetingRuns.find(in: snapshot?.events ?? [], now: now).prefix(8))
    center.getPendingNotificationRequests { [center] requests in
      center.removePendingNotificationRequests(
        withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("reset.") })
      for run in runs {
        let content = UNMutableNotificationContent()
        content.title = "Back-to-backs are over"
        content.body = MeetingRuns.body(for: run)
        content.categoryIdentifier = Self.category
        content.sound = .default
        let fire = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: run.end)
        center.add(UNNotificationRequest(
          identifier: "reset.\(Int(run.end.timeIntervalSince1970))",
          content: content,
          trigger: UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)))
      }
    }
  }

  // MARK: UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    guard response.notification.request.content.categoryIdentifier == Self.category else { return }
    await MainActor.run { resetRequested = true }
  }
}
