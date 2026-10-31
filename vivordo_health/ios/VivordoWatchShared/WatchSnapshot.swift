import Foundation

/// The slice of the phone's snapshot the watch shows, read from the watch's
/// app group. The keys are the ones the phone writes for Siri and widgets;
/// `WatchSnapshotBridge` (phone) and `WatchSnapshotStore` (watch) move them
/// across unchanged. Compiled into the watch app and its complications.
struct WatchSnapshot: Equatable {
  static let appGroup = "group.com.vivordo.health"

  struct Event: Equatable {
    let title: String
    let start: Date
    let end: Date
  }

  let capacityScore: Int?
  let capacityLabel: String
  let capacityNote: String
  let demand: Int?
  let demandHeadline: String
  let stressScore: Int?
  let latestHeartRate: Int?
  let sleepHours: Double?
  /// Every timed event the phone sent (this week), unsorted.
  let events: [Event]
  let nextEvent: Event?
  let updatedAt: Date?

  /// Nil until the phone has sent anything.
  static func load(
    defaults: UserDefaults? = UserDefaults(suiteName: appGroup),
    now: Date = Date()
  ) -> WatchSnapshot? {
    guard let defaults, defaults.object(forKey: "updatedAt") != nil else { return nil }
    let today = dayKey(now)
    let capacityIsToday = defaults.string(forKey: "capacityDay") == today
    let hasCapacity = defaults.bool(forKey: "dashboardHasCapacity") && capacityIsToday
    let hasStress = defaults.bool(forKey: "dashboardHasStress")
    let events = events(defaults)
    return WatchSnapshot(
      capacityScore: hasCapacity ? int(defaults, "capacityScore") : nil,
      capacityLabel: hasCapacity ? defaults.string(forKey: "capacityLabel") ?? "" : "",
      capacityNote: hasCapacity ? defaults.string(forKey: "capacityNote") ?? "" : "",
      demand: int(defaults, "siriDemand"),
      demandHeadline: defaults.string(forKey: "siriDemandHeadline") ?? "",
      stressScore: hasStress ? int(defaults, "stressScore") : nil,
      latestHeartRate: int(defaults, "siriHeartRateLatest"),
      sleepHours: double(defaults, "siriSleepHours"),
      events: events,
      nextEvent: events.filter { $0.end > now }.min { $0.start < $1.start },
      updatedAt: seconds(defaults, "updatedAt")
    )
  }

  // MARK: Readers

  private static func int(_ d: UserDefaults, _ key: String) -> Int? {
    d.object(forKey: key) == nil ? nil : d.integer(forKey: key)
  }

  private static func double(_ d: UserDefaults, _ key: String) -> Double? {
    guard d.object(forKey: key) != nil else { return nil }
    let value = d.double(forKey: key)
    return value > 0 ? value : nil
  }

  /// `updatedAt` is seconds since 1970; every other date key is milliseconds.
  private static func seconds(_ d: UserDefaults, _ key: String) -> Date? {
    let value = d.double(forKey: key)
    return value > 0 ? Date(timeIntervalSince1970: value) : nil
  }

  private static func events(_ d: UserDefaults) -> [Event] {
    let raw = d.array(forKey: "siriCalendarEvents") as? [[String: Any]]
      ?? d.array(forKey: "calendarEvents") as? [[String: Any]] ?? []
    return raw.compactMap { item -> Event? in
      guard let title = item["title"] as? String,
            let startMs = (item["startAt"] as? NSNumber)?.doubleValue,
            item["isAllDay"] as? Bool != true else { return nil }
      let endMs = (item["endAt"] as? NSNumber)?.doubleValue ?? startMs
      return Event(
        title: title,
        start: Date(timeIntervalSince1970: startMs / 1000),
        end: Date(timeIntervalSince1970: endMs / 1000)
      )
    }
  }

  static func dayKey(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
