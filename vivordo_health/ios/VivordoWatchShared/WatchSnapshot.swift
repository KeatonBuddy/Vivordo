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

  struct Priority: Equatable, Identifiable {
    let id: String
    let title: String
    /// "9:00 AM", "All day" or "Anytime", as My Day shows it.
    let time: String
    /// Set for a timed priority.
    let start: Date?
    let completed: Bool
  }

  /// A saved workout from the phone (`watchWorkouts`).
  struct Workout: Equatable, Identifiable {
    struct Exercise: Equatable {
      struct Set: Equatable {
        let weight: Double
        let reps: Int
      }
      let name: String
      let category: String
      /// Target sets, when the routine has them.
      let targetSets: Int?
      /// The sets from the last time it was done, empty if never.
      let last: [Set]
    }
    let id: String
    let name: String
    let exercises: [Exercise]
  }

  let capacityScore: Int?
  let capacityLabel: String
  let capacityNote: String
  let demand: Int?
  let demandHeadline: String
  let stressScore: Int?
  let stressDrivers: [String]
  let latestHeartRate: Int?
  /// Today's average so far, from the phone.
  let averageHeartRate: Int?
  let sleepHours: Double?
  let steps: Int?
  let stepsGoal: Int?
  let activeCalories: Int?
  let activeCaloriesGoal: Int?
  /// lighter, steady, building, high, strained or "" while learning.
  let trainingState: String
  /// Today's priorities, habits left out; empty when the phone's list is
  /// from another day.
  let priorities: [Priority]
  /// Every timed event the phone sent (this week), unsorted.
  let workouts: [Workout]
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
      stressDrivers: hasStress ? defaults.stringArray(forKey: "stressDrivers") ?? [] : [],
      latestHeartRate: positive(defaults, "siriHeartRateLatest"),
      averageHeartRate: positive(defaults, "siriHeartRateAverage"),
      sleepHours: double(defaults, "siriSleepHours"),
      steps: int(defaults, "steps"),
      stepsGoal: positive(defaults, "stepsGoal"),
      activeCalories: int(defaults, "activeCalories"),
      activeCaloriesGoal: positive(defaults, "activeCaloriesGoal"),
      trainingState: defaults.string(forKey: "siriTrainingState") ?? "",
      priorities: defaults.string(forKey: "dashboardPrioritiesDay") == today
        ? priorities(defaults) : [],
      workouts: workouts(defaults),
      events: events,
      nextEvent: events.filter { $0.end > now }.min { $0.start < $1.start },
      updatedAt: seconds(defaults, "updatedAt")
    )
  }

  // MARK: Readers

  private static func int(_ d: UserDefaults, _ key: String) -> Int? {
    d.object(forKey: key) == nil ? nil : d.integer(forKey: key)
  }

  /// Siri keys use -1 (and 0) for "none".
  private static func positive(_ d: UserDefaults, _ key: String) -> Int? {
    let value = d.integer(forKey: key)
    return value > 0 ? value : nil
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

  private static func priorities(_ d: UserDefaults) -> [Priority] {
    let raw = d.array(forKey: "dashboardPriorities") as? [[String: Any]] ?? []
    return raw.compactMap { item in
      guard let id = item["id"] as? String, let title = item["title"] as? String,
            item["habit"] as? Bool != true else { return nil }
      let startMs = (item["startAt"] as? NSNumber)?.doubleValue
      return Priority(
        id: id, title: title,
        time: item["time"] as? String ?? "",
        start: item["isAllDay"] as? Bool == true ? nil
          : startMs.map { Date(timeIntervalSince1970: $0 / 1000) },
        completed: item["completed"] as? Bool == true
      )
    }
  }

  private static func workouts(_ d: UserDefaults) -> [Workout] {
    let raw = d.array(forKey: "watchWorkouts") as? [[String: Any]] ?? []
    return raw.compactMap { item in
      guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
      let exercises = (item["exercises"] as? [[String: Any]] ?? []).compactMap { e -> Workout.Exercise? in
        guard let name = e["name"] as? String else { return nil }
        let last = (e["last"] as? [[String: Any]] ?? []).compactMap { set -> Workout.Exercise.Set? in
          guard let w = (set["w"] as? NSNumber)?.doubleValue,
                let r = (set["r"] as? NSNumber)?.intValue else { return nil }
          return .init(weight: w, reps: r)
        }
        return .init(
          name: name, category: e["category"] as? String ?? "Other",
          targetSets: (e["sets"] as? NSNumber)?.intValue, last: last
        )
      }
      return exercises.isEmpty ? nil : Workout(id: id, name: name, exercises: exercises)
    }
  }

  static func dayKey(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
