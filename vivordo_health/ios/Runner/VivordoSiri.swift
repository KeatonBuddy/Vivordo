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

enum VivordoHealthMetric: String, CaseIterable, Sendable {
  case stress
  case sleep
  case heartRate
  case steps
  case wellness

  var destinationURL: URL {
    URL(string: "com.vivordo.health://widget/\(rawValue.lowercased())")!
  }
}

struct VivordoSiriAnswer: Equatable, Sendable {
  let dialog: String
  let destinationURL: URL
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

/// Converts the cached snapshot into short, privacy-safe spoken responses.
/// Keeping this separate from AppIntent makes every response path unit-testable.
struct VivordoSiriQueryService {
  static let maximumSnapshotAge: TimeInterval = 6 * 60 * 60

  private let store: VivordoSnapshotStore

  init(store: VivordoSnapshotStore = VivordoSnapshotStore()) {
    self.store = store
  }

  func answer(for metric: VivordoHealthMetric, now: Date = Date()) -> VivordoSiriAnswer {
    let destination = metric.destinationURL
    let snapshot: VivordoSiriSnapshot
    do {
      snapshot = try store.load()
    } catch {
      return VivordoSiriAnswer(
        dialog: "Open Vivordo to sign in and refresh your health data.",
        destinationURL: destination
      )
    }

    guard store.isFresh(snapshot, now: now, maximumAge: Self.maximumSnapshotAge) else {
      return VivordoSiriAnswer(
        dialog: "Your Vivordo data needs a refresh. Open the app to update it.",
        destinationURL: destination
      )
    }

    let dialog: String
    switch metric {
    case .stress:
      if let score = snapshot.stressScore {
        let drivers = snapshot.stressDrivers.prefix(2)
        let detail = drivers.isEmpty ? "" : " Your main drivers are \(drivers.joined(separator: " and "))."
        dialog = "Your Vivordo stress score is \(score) out of 100.\(detail)"
      } else {
        dialog = "Vivordo doesn't have a stress score for you yet today."
      }
    case .sleep:
      if let hours = snapshot.sleepHours {
        dialog = "Vivordo recorded \(Self.hoursText(hours)) of sleep."
      } else {
        dialog = "Vivordo doesn't have sleep data for you yet."
      }
    case .heartRate:
      if let beatsPerMinute = snapshot.latestHeartRate {
        dialog = "Your latest heart rate is \(beatsPerMinute) beats per minute."
      } else {
        dialog = "Vivordo doesn't have a recent heart rate reading for you."
      }
    case .steps:
      if let steps = snapshot.steps {
        dialog = "You've taken \(steps.formatted()) steps today."
      } else {
        dialog = "Vivordo doesn't have a step count for you yet today."
      }
    case .wellness:
      if let score = snapshot.wellnessScore {
        dialog = "Your Vivordo wellness score is \(score) out of 100 today."
      } else {
        dialog = "Vivordo doesn't have a wellness score for you yet today."
      }
    }
    return VivordoSiriAnswer(dialog: dialog, destinationURL: destination)
  }

  private static func hoursText(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    let wholeHours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if wholeHours == 0 { return "\(minutes) minutes" }
    if minutes == 0 { return "\(wholeHours) hours" }
    return "\(wholeHours) hours and \(minutes) minutes"
  }
}

private protocol VivordoHealthQueryIntent: AppIntent {
  static var metric: VivordoHealthMetric { get }
}

private extension VivordoHealthQueryIntent {
  func healthResult() -> some IntentResult & ProvidesDialog & OpensIntent {
    let answer = VivordoSiriQueryService().answer(for: Self.metric)
    return .result(
      opensIntent: OpenURLIntent(answer.destinationURL),
      dialog: IntentDialog(stringLiteral: answer.dialog)
    )
  }
}

struct CheckStressIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Stress Score"
  static var description = IntentDescription("Get today's Vivordo stress score.")
  static let metric = VivordoHealthMetric.stress

  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    healthResult()
  }
}

struct CheckSleepIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Sleep"
  static var description = IntentDescription("Get your latest sleep duration from Vivordo.")
  static let metric = VivordoHealthMetric.sleep

  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    healthResult()
  }
}

struct CheckHeartRateIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Heart Rate"
  static var description = IntentDescription("Get your latest heart rate from Vivordo.")
  static let metric = VivordoHealthMetric.heartRate

  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    healthResult()
  }
}

struct CheckStepsIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Steps"
  static var description = IntentDescription("Get today's step count from Vivordo.")
  static let metric = VivordoHealthMetric.steps

  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    healthResult()
  }
}

struct CheckWellnessIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Wellness Score"
  static var description = IntentDescription("Get today's Vivordo wellness score.")
  static let metric = VivordoHealthMetric.wellness

  func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
    healthResult()
  }
}

/// A small discovery intent lets users launch Vivordo independently of a
/// health query.
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
    AppShortcut(
      intent: CheckStressIntent(),
      phrases: ["What's my stress score in \(.applicationName)", "Check my stress with \(.applicationName)"],
      shortTitle: "Stress Score",
      systemImageName: "waveform.path.ecg"
    )
    AppShortcut(
      intent: CheckSleepIntent(),
      phrases: ["How did I sleep with \(.applicationName)", "Check my sleep in \(.applicationName)"],
      shortTitle: "Sleep",
      systemImageName: "bed.double.fill"
    )
    AppShortcut(
      intent: CheckHeartRateIntent(),
      phrases: ["What's my heart rate in \(.applicationName)", "Check my heart rate with \(.applicationName)"],
      shortTitle: "Heart Rate",
      systemImageName: "heart.fill"
    )
    AppShortcut(
      intent: CheckStepsIntent(),
      phrases: ["How many steps in \(.applicationName)", "Check my steps with \(.applicationName)"],
      shortTitle: "Steps",
      systemImageName: "figure.walk"
    )
    AppShortcut(
      intent: CheckWellnessIntent(),
      phrases: [
        "What's my wellness score in \(.applicationName)",
        "Tell me my wellness score with \(.applicationName)"
      ],
      shortTitle: "Wellness Score",
      systemImageName: "heart.text.square.fill"
    )
  }
}
