import AppIntents
import Foundation
import SwiftUI

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

enum VivordoHealthMetric: String, Sendable {
  case stress
  case sleep
  case heartRate
  case steps
  case wellness

}

struct VivordoSiriAnswer: Equatable, Sendable {
  let metric: VivordoHealthMetric
  let dialog: String
  let title: String
  let value: String
  let unit: String?
  let status: String
  let detail: String?
  let progress: Double?
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
    let snapshot: VivordoSiriSnapshot
    do {
      snapshot = try store.load()
    } catch {
      return VivordoSiriAnswer(
        metric: metric,
        dialog: "Open Vivordo to sign in and refresh your health data.",
        title: Self.title(for: metric),
        value: "--",
        unit: nil,
        status: "Data unavailable",
        detail: "Open Vivordo to sign in and refresh your health data.",
        progress: nil
      )
    }

    guard store.isFresh(snapshot, now: now, maximumAge: Self.maximumSnapshotAge) else {
      return VivordoSiriAnswer(
        metric: metric,
        dialog: "Your Vivordo data needs a refresh. Open the app to update it.",
        title: Self.title(for: metric),
        value: "--",
        unit: nil,
        status: "Refresh needed",
        detail: "Open Vivordo to update your health data.",
        progress: nil
      )
    }

    switch metric {
    case .stress:
      if let score = snapshot.stressScore {
        let drivers = snapshot.stressDrivers.prefix(2)
        let detail = drivers.isEmpty ? "" : " Your main drivers are \(drivers.joined(separator: " and "))."
        return VivordoSiriAnswer(
          metric: metric,
          dialog: "Your Vivordo stress score is \(score) out of 100.\(detail)",
          title: "Stress Score",
          value: "\(score)",
          unit: "out of 100",
          status: Self.stressStatus(score),
          detail: drivers.isEmpty ? "Today" : "Main drivers: \(drivers.joined(separator: " • "))",
          progress: Double(score) / 100
        )
      } else {
        return Self.missing(metric, dialog: "Vivordo doesn't have a stress score for you yet today.")
      }
    case .sleep:
      if let hours = snapshot.sleepHours {
        return VivordoSiriAnswer(
          metric: metric,
          dialog: "Vivordo recorded \(Self.hoursText(hours)) of sleep.",
          title: "Sleep",
          value: Self.shortHoursText(hours),
          unit: nil,
          status: Self.sleepStatus(hours),
          detail: snapshot.sleepStages.isEmpty ? "Latest sleep" : snapshot.sleepStages.prefix(4).joined(separator: " • "),
          progress: min(hours / 8, 1)
        )
      } else {
        return Self.missing(metric, dialog: "Vivordo doesn't have sleep data for you yet.")
      }
    case .heartRate:
      if let beatsPerMinute = snapshot.latestHeartRate {
        return VivordoSiriAnswer(
          metric: metric,
          dialog: "Your latest heart rate is \(beatsPerMinute) beats per minute.",
          title: "Heart Rate",
          value: "\(beatsPerMinute)",
          unit: "BPM",
          status: "Latest reading",
          detail: Self.heartRateDetail(snapshot),
          progress: nil
        )
      } else {
        return Self.missing(metric, dialog: "Vivordo doesn't have a recent heart rate reading for you.")
      }
    case .steps:
      if let steps = snapshot.steps {
        return VivordoSiriAnswer(
          metric: metric,
          dialog: "You've taken \(steps.formatted()) steps today.",
          title: "Steps",
          value: steps.formatted(),
          unit: "steps",
          status: "Today",
          detail: nil,
          progress: min(Double(steps) / 10_000, 1)
        )
      } else {
        return Self.missing(metric, dialog: "Vivordo doesn't have a step count for you yet today.")
      }
    case .wellness:
      if let score = snapshot.wellnessScore {
        return VivordoSiriAnswer(
          metric: metric,
          dialog: "Your Vivordo wellness score is \(score) out of 100 today.",
          title: "Wellness Score",
          value: "\(score)",
          unit: "out of 100",
          status: Self.wellnessStatus(score),
          detail: "Today",
          progress: Double(score) / 100
        )
      } else {
        return Self.missing(metric, dialog: "Vivordo doesn't have a wellness score for you yet today.")
      }
    }
  }

  private static func missing(_ metric: VivordoHealthMetric, dialog: String) -> VivordoSiriAnswer {
    VivordoSiriAnswer(
      metric: metric,
      dialog: dialog,
      title: title(for: metric),
      value: "--",
      unit: nil,
      status: "Not available yet",
      detail: "Refresh Vivordo after new health data is recorded.",
      progress: nil
    )
  }

  private static func title(for metric: VivordoHealthMetric) -> String {
    switch metric {
    case .stress: "Stress Score"
    case .sleep: "Sleep"
    case .heartRate: "Heart Rate"
    case .steps: "Steps"
    case .wellness: "Wellness Score"
    }
  }

  private static func stressStatus(_ score: Int) -> String {
    if score < 34 { return "Low stress" }
    if score < 67 { return "Moderate stress" }
    return "High stress"
  }

  private static func wellnessStatus(_ score: Int) -> String {
    if score >= 80 { return "Great" }
    if score >= 60 { return "Good" }
    if score >= 40 { return "Fair" }
    return "Needs attention"
  }

  private static func sleepStatus(_ hours: Double) -> String {
    if hours >= 7 { return "Restful night" }
    if hours >= 6 { return "A little short" }
    return "Short sleep"
  }

  private static func shortHoursText(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    let wholeHours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if wholeHours == 0 { return "\(minutes) min" }
    if minutes == 0 { return "\(wholeHours) hr" }
    return "\(wholeHours) hr \(minutes) min"
  }

  private static func heartRateDetail(_ snapshot: VivordoSiriSnapshot) -> String? {
    guard let minimum = snapshot.minimumHeartRate,
          let maximum = snapshot.maximumHeartRate else { return nil }
    return "Today's range: \(Int(minimum.rounded()))–\(Int(maximum.rounded())) BPM"
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

/// A compact, read-only result that system surfaces can show without opening
/// the Flutter application. Siri still receives `dialog` as the spoken and
/// accessibility fallback when a visual result isn't appropriate.
struct VivordoMetricSnippetView: View {
  let answer: VivordoSiriAnswer

  private let accent = Color(red: 0.49, green: 0.32, blue: 0.96)

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(answer.title, systemImage: systemImage)
        .font(.headline)
        .foregroundStyle(.secondary)

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(answer.value)
          .font(.system(size: 42, weight: .bold, design: .rounded))
          .contentTransition(.numericText())

        if let unit = answer.unit {
          Text(unit)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        if answer.metric == .heartRate, answer.value != "--" {
          Image(systemName: "waveform.path.ecg")
            .font(.system(size: 34, weight: .medium))
            .foregroundStyle(accent)
            .accessibilityHidden(true)
        } else if let progress = answer.progress {
          progressRing(progress)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(answer.status)
          .font(.headline)
          .foregroundStyle(accent)
        if let detail = answer.detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(answer.dialog)
  }

  private var systemImage: String {
    switch answer.metric {
    case .stress: "waveform.path.ecg"
    case .sleep: "bed.double.fill"
    case .heartRate: "heart.fill"
    case .steps: "figure.walk"
    case .wellness: "heart.text.square.fill"
    }
  }

  private func progressRing(_ progress: Double) -> some View {
    ZStack {
      Circle()
        .stroke(accent.opacity(0.18), lineWidth: 7)
      Circle()
        .trim(from: 0, to: max(0, min(progress, 1)))
        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: 54, height: 54)
    .accessibilityHidden(true)
  }
}

private protocol VivordoHealthQueryIntent: AppIntent {
  static var metric: VivordoHealthMetric { get }
}

private extension VivordoHealthQueryIntent {
  func healthResult() -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    let answer = VivordoSiriQueryService().answer(for: Self.metric)
    return .result(
      dialog: IntentDialog(stringLiteral: answer.dialog),
      view: VivordoMetricSnippetView(answer: answer)
    )
  }
}

struct CheckStressIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Stress Score"
  static var description = IntentDescription("Get today's Vivordo stress score.")
  static let metric = VivordoHealthMetric.stress

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    healthResult()
  }
}

struct CheckSleepIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Sleep"
  static var description = IntentDescription("Get your latest sleep duration from Vivordo.")
  static let metric = VivordoHealthMetric.sleep

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    healthResult()
  }
}

struct CheckHeartRateIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Heart Rate"
  static var description = IntentDescription("Get your latest heart rate from Vivordo.")
  static let metric = VivordoHealthMetric.heartRate

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    healthResult()
  }
}

struct CheckStepsIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Check Steps"
  static var description = IntentDescription("Get today's step count from Vivordo.")
  static let metric = VivordoHealthMetric.steps

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    healthResult()
  }
}

struct GetWellnessScoreIntent: VivordoHealthQueryIntent {
  static var title: LocalizedStringResource = "Get Wellness Score"
  static var description = IntentDescription("Get today's Vivordo wellness score.")
  static let metric = VivordoHealthMetric.wellness

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
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
      phrases: [
        "What's my stress score in \(.applicationName)",
        "What's my \(.applicationName) stress score",
        "Tell me my stress score with \(.applicationName)",
        "Check my stress score in \(.applicationName)"
      ],
      shortTitle: "Stress Score",
      systemImageName: "waveform.path.ecg"
    )
    AppShortcut(
      intent: CheckSleepIntent(),
      phrases: [
        "How did I sleep with \(.applicationName)",
        "How did I sleep in \(.applicationName)",
        "What's my \(.applicationName) sleep",
        "Tell me my sleep from \(.applicationName)"
      ],
      shortTitle: "Sleep",
      systemImageName: "bed.double.fill"
    )
    AppShortcut(
      intent: CheckHeartRateIntent(),
      phrases: [
        "What's my heart rate in \(.applicationName)",
        "What's my \(.applicationName) heart rate",
        "Tell me my heart rate with \(.applicationName)",
        "Check my pulse in \(.applicationName)"
      ],
      shortTitle: "Heart Rate",
      systemImageName: "heart.fill"
    )
    AppShortcut(
      intent: CheckStepsIntent(),
      phrases: [
        "How many steps in \(.applicationName)",
        "How many steps have I taken in \(.applicationName)",
        "What's my \(.applicationName) step count",
        "Tell me my steps with \(.applicationName)"
      ],
      shortTitle: "Steps",
      systemImageName: "figure.walk"
    )
    AppShortcut(
      intent: GetWellnessScoreIntent(),
      phrases: [
        "What's my wellness score in \(.applicationName)",
        "What's my \(.applicationName) wellness score",
        "Tell me my wellness score with \(.applicationName)",
        "Check my wellness score in \(.applicationName)"
      ],
      shortTitle: "Wellness Score",
      systemImageName: "heart.text.square.fill"
    )
  }
}
