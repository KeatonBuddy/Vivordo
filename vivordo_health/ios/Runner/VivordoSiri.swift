import AppIntents
import Foundation

/// The native boundary for Vivordo information exposed to Siri.
///
/// Flutter remains responsible for Firebase, HealthKit, and business logic. It
/// publishes a small, sanitized snapshot into the existing App Group. Intents
/// read that snapshot so they remain deterministic when the Flutter engine is
/// suspended or the application isn't running.
enum VivordoSiriConfiguration {
  static let appGroupIdentifier = "group.com.vivordo.health"
  static let supportedSnapshotSchemaVersion = 1
}

struct VivordoSiriSnapshot: Equatable, Sendable {
  let schemaVersion: Int
  let accountGeneration: String
  let publishedAt: Date
  let dataDay: String
  let stressScore: Int?
  let stressUpdatedAt: Date?
  let stressDrivers: [String]
  let wellnessScore: Int?
  let steps: Int?
  let activeCalories: Int?
  let exerciseMinutes: Int?
  let latestHeartRate: Int?
  let latestHeartRateAt: Date?
  let averageHeartRate: Double?
  let minimumHeartRate: Double?
  let maximumHeartRate: Double?
  let sleepHours: Double?
  let sleepUpdatedAt: Date?
  let sleepStages: [String]
}

enum VivordoSnapshotError: Error, Equatable {
  case unavailable
  case unsupportedSchema(Int)
  case accountUnavailable
}

struct VivordoSnapshotStore {
  private let defaults: UserDefaults?

  init(defaults: UserDefaults? = UserDefaults(
    suiteName: VivordoSiriConfiguration.appGroupIdentifier
  )) {
    self.defaults = defaults
  }

  func load() throws -> VivordoSiriSnapshot {
    guard let defaults else { throw VivordoSnapshotError.unavailable }
    let schemaVersion = defaults.integer(forKey: "siriSchemaVersion")
    guard schemaVersion == VivordoSiriConfiguration.supportedSnapshotSchemaVersion else {
      if schemaVersion == 0 { throw VivordoSnapshotError.unavailable }
      throw VivordoSnapshotError.unsupportedSchema(schemaVersion)
    }

    let generation = defaults.string(forKey: "siriAccountGeneration") ?? ""
    guard !generation.isEmpty else { throw VivordoSnapshotError.accountUnavailable }
    guard let publishedAt = date(defaults, key: "siriPublishedAt") else {
      throw VivordoSnapshotError.unavailable
    }

    return VivordoSiriSnapshot(
      schemaVersion: schemaVersion,
      accountGeneration: generation,
      publishedAt: publishedAt,
      dataDay: defaults.string(forKey: "siriDataDay") ?? "",
      stressScore: positiveInt(defaults, key: "siriStressScore", allowZero: true),
      stressUpdatedAt: date(defaults, key: "stressUpdatedAt"),
      stressDrivers: stringArray(defaults, key: "stressDrivers"),
      wellnessScore: positiveInt(defaults, key: "siriWellnessScore", allowZero: true),
      steps: positiveInt(defaults, key: "steps", allowZero: true),
      activeCalories: positiveInt(defaults, key: "activeCalories", allowZero: true),
      exerciseMinutes: positiveInt(defaults, key: "exerciseMinutes", allowZero: true),
      latestHeartRate: positiveInt(defaults, key: "siriHeartRateLatest"),
      latestHeartRateAt: date(defaults, key: "heartRateLatestAt"),
      averageHeartRate: positiveDouble(defaults, key: "siriHeartRateAverage"),
      minimumHeartRate: positiveDouble(defaults, key: "siriHeartRateMinimum"),
      maximumHeartRate: positiveDouble(defaults, key: "siriHeartRateMaximum"),
      sleepHours: positiveDouble(defaults, key: "siriSleepHours"),
      sleepUpdatedAt: date(defaults, key: "sleepUpdatedAt"),
      sleepStages: stringArray(defaults, key: "sleepStages")
    )
  }

  func isFresh(_ snapshot: VivordoSiriSnapshot, now: Date = Date(),
               maximumAge: TimeInterval) -> Bool {
    now.timeIntervalSince(snapshot.publishedAt) >= 0 &&
      now.timeIntervalSince(snapshot.publishedAt) <= maximumAge
  }

  private func date(_ defaults: UserDefaults, key: String) -> Date? {
    let milliseconds = defaults.double(forKey: key)
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
  }

  private func positiveInt(_ defaults: UserDefaults, key: String,
                           allowZero: Bool = false) -> Int? {
    guard defaults.object(forKey: key) != nil else { return nil }
    let value = defaults.integer(forKey: key)
    return value > 0 || (allowZero && value == 0) ? value : nil
  }

  private func positiveDouble(_ defaults: UserDefaults, key: String) -> Double? {
    guard defaults.object(forKey: key) != nil else { return nil }
    let value = defaults.double(forKey: key)
    return value > 0 ? value : nil
  }

  private func stringArray(_ defaults: UserDefaults, key: String) -> [String] {
    (defaults.array(forKey: key) as? [String]) ?? []
  }
}

/// A small discovery intent verifies that the App Intents catalog is wired.
/// Health query intents are intentionally added in Phase 2 after the snapshot
/// contract has been exercised on-device.
struct OpenVivordoIntent: AppIntent {
  static var title: LocalizedStringResource = "Open Vivordo"
  static var description = IntentDescription("Open the Vivordo app.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    .result()
  }
}

struct VivordoAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenVivordoIntent(),
      phrases: [
        "Open \(.applicationName)",
        "Show \(.applicationName)"
      ],
      shortTitle: "Open Vivordo",
      systemImageName: "heart.text.square"
    )
  }
}
