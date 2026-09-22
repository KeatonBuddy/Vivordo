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

struct VivordoCalendarEvent: Equatable, Identifiable, Sendable {
  let title: String
  let start: Date
  let end: Date
  let isAllDay: Bool
  let kind: String

  var id: String { "\(title)|\(start.timeIntervalSince1970)" }
}

struct VivordoCalendarSnapshot: Equatable, Sendable {
  let updatedAt: Date
  let events: [VivordoCalendarEvent]
}

enum VivordoCalendarSnapshotError: Error, Equatable {
  case unavailable
}

struct VivordoCalendarSnapshotStore {
  private let defaults: UserDefaults?

  init(defaults: UserDefaults? = UserDefaults(
    suiteName: VivordoSiriConfiguration.appGroupIdentifier
  )) {
    self.defaults = defaults
  }

  func load() throws -> VivordoCalendarSnapshot {
    guard let defaults else {
      throw VivordoCalendarSnapshotError.unavailable
    }
    let rawEvents =
      defaults.array(forKey: "siriCalendarEvents") as? [[String: Any]] ??
      defaults.array(forKey: "calendarEvents") as? [[String: Any]]
    guard let rawEvents else { throw VivordoCalendarSnapshotError.unavailable }
    let updatedMilliseconds = defaults.double(forKey: "calendarWeekUpdatedAt")
    guard updatedMilliseconds > 0 else {
      throw VivordoCalendarSnapshotError.unavailable
    }

    let events = rawEvents.compactMap { raw -> VivordoCalendarEvent? in
      guard let title = raw["title"] as? String,
            let startMilliseconds = raw["startAt"] as? NSNumber else { return nil }
      let endMilliseconds = raw["endAt"] as? NSNumber
      let start = Date(timeIntervalSince1970: startMilliseconds.doubleValue / 1_000)
      let end = Date(
        timeIntervalSince1970: (endMilliseconds?.doubleValue ?? startMilliseconds.doubleValue) / 1_000
      )
      return VivordoCalendarEvent(
        title: title,
        start: start,
        end: end,
        isAllDay: raw["isAllDay"] as? Bool ?? false,
        kind: raw["kind"] as? String ?? "calendar"
      )
    }
    .sorted { $0.start < $1.start }

    return VivordoCalendarSnapshot(
      updatedAt: Date(timeIntervalSince1970: updatedMilliseconds / 1_000),
      events: events
    )
  }

  func isFresh(
    _ snapshot: VivordoCalendarSnapshot,
    now: Date = .now,
    maximumAge: TimeInterval
  ) -> Bool {
    now.timeIntervalSince(snapshot.updatedAt) >= 0 &&
      now.timeIntervalSince(snapshot.updatedAt) <= maximumAge
  }
}

enum VivordoCalendarQuery: Sendable {
  case today
  case next
}

struct VivordoCalendarAnswer: Equatable, Sendable {
  let dialog: String
  let title: String
  let status: String
  let events: [VivordoCalendarEvent]
  let detail: String?
}

struct VivordoCalendarQueryService {
  static let maximumSnapshotAge: TimeInterval = 2 * 60 * 60

  private let store: VivordoCalendarSnapshotStore
  private let calendar: Calendar

  init(
    store: VivordoCalendarSnapshotStore = VivordoCalendarSnapshotStore(),
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.store = store
    self.calendar = calendar
  }

  func answer(for query: VivordoCalendarQuery, now: Date = .now) -> VivordoCalendarAnswer {
    let snapshot: VivordoCalendarSnapshot
    do {
      snapshot = try store.load()
    } catch {
      return unavailable(
        dialog: "Open Vivordo to connect and refresh your calendar.",
        status: "Calendar unavailable"
      )
    }

    guard store.isFresh(snapshot, now: now, maximumAge: Self.maximumSnapshotAge) else {
      return unavailable(
        dialog: "Your Vivordo calendar needs a refresh. Open the app to update it.",
        status: "Refresh needed"
      )
    }

    switch query {
    case .today:
      let remaining = snapshot.events.filter {
        calendar.isDate($0.start, inSameDayAs: now) && $0.end > now
      }
      guard let first = remaining.first else {
        return VivordoCalendarAnswer(
          dialog: "You have no more events today in Vivordo.",
          title: "Today's Schedule",
          status: "You're clear",
          events: [],
          detail: "No remaining events"
        )
      }
      let countText = remaining.count == 1 ? "one event" : "\(remaining.count) events"
      return VivordoCalendarAnswer(
        dialog: "You have \(countText) remaining today in Vivordo. Next is \(first.title) \(spokenTime(for: first, now: now)).",
        title: "Today's Schedule",
        status: remaining.count == 1 ? "1 event remaining" : "\(remaining.count) events remaining",
        events: Array(remaining.prefix(3)),
        detail: remaining.count > 3 ? "+ \(remaining.count - 3) more" : nil
      )

    case .next:
      guard let event = snapshot.events.first(where: { $0.end > now }) else {
        return VivordoCalendarAnswer(
          dialog: "You don't have another event in Vivordo's saved schedule.",
          title: "Next Event",
          status: "Nothing scheduled",
          events: [],
          detail: nil
        )
      }
      return VivordoCalendarAnswer(
        dialog: "Your next Vivordo event is \(event.title) \(spokenTime(for: event, now: now)).",
        title: "Next Event",
        status: relativeDay(for: event.start, now: now),
        events: [event],
        detail: nil
      )
    }
  }

  private func unavailable(dialog: String, status: String) -> VivordoCalendarAnswer {
    VivordoCalendarAnswer(
      dialog: dialog,
      title: "Vivordo Calendar",
      status: status,
      events: [],
      detail: "Open Vivordo to update your schedule."
    )
  }

  private func spokenTime(for event: VivordoCalendarEvent, now: Date) -> String {
    if event.isAllDay { return "all day" }
    let time = event.start.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(event.start) || calendar.isDate(event.start, inSameDayAs: now) {
      return "at \(time)"
    }
    if calendar.isDateInTomorrow(event.start) ||
        calendar.isDate(event.start, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now) {
      return "tomorrow at \(time)"
    }
    return "on \(event.start.formatted(.dateTime.weekday(.wide).hour().minute()))"
  }

  private func relativeDay(for date: Date, now: Date) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
       calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
    return date.formatted(.dateTime.weekday(.wide))
  }
}

struct VivordoCalendarSnippetView: View {
  let answer: VivordoCalendarAnswer

  private let accent = Color(red: 0.49, green: 0.32, blue: 0.96)

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(answer.title, systemImage: "calendar")
        .font(.headline)
        .foregroundStyle(.secondary)

      Text(answer.status)
        .font(.title2.bold())

      if answer.events.isEmpty {
        if let detail = answer.detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(spacing: 10) {
          ForEach(answer.events) { event in
            HStack(spacing: 12) {
              Image(systemName: symbol(for: event.kind))
                .foregroundStyle(accent)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                  .font(.headline)
                  .lineLimit(1)
                Text(timeText(for: event))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
            }
          }
        }
        if let detail = answer.detail {
          Text(detail)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(answer.dialog)
  }

  private func timeText(for event: VivordoCalendarEvent) -> String {
    if event.isAllDay { return "All day" }
    return "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
  }

  private func symbol(for kind: String) -> String {
    switch kind {
    case "running": "figure.run"
    case "fitness": "dumbbell.fill"
    case "sport": "sportscourt.fill"
    default: "calendar"
    }
  }
}

private protocol VivordoCalendarQueryIntent: AppIntent {
  static var query: VivordoCalendarQuery { get }
}

private extension VivordoCalendarQueryIntent {
  func calendarResult() -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    let answer = VivordoCalendarQueryService().answer(for: Self.query)
    return .result(
      dialog: IntentDialog(stringLiteral: answer.dialog),
      view: VivordoCalendarSnippetView(answer: answer)
    )
  }
}

struct GetTodayScheduleIntent: VivordoCalendarQueryIntent {
  static var title: LocalizedStringResource = "Get Today's Schedule"
  static var description = IntentDescription("Get today's remaining events from Vivordo.")
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let query = VivordoCalendarQuery.today

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    calendarResult()
  }
}

struct GetNextCalendarEventIntent: VivordoCalendarQueryIntent {
  static var title: LocalizedStringResource = "Get Next Calendar Event"
  static var description = IntentDescription("Get the next event from Vivordo.")
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let query = VivordoCalendarQuery.next

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    calendarResult()
  }
}

enum VivordoPlanningQuery: Sendable {
  case scheduleLoad
  case recoveryWindow
}

struct VivordoRecoveryWindow: Equatable, Sendable {
  let start: Date
  let end: Date
}

struct VivordoPlanningAnswer: Equatable, Sendable {
  let dialog: String
  let title: String
  let headline: String
  let detail: String
  let drivers: [String]
  let events: [VivordoCalendarEvent]
  let priorities: [String]
  let loadScore: Int?
  let recoveryWindow: VivordoRecoveryWindow?
}

/// Combines Vivordo's cached health context with the user's saved schedule.
/// The load score describes calendar density only; it is deliberately kept
/// separate from Vivordo's physiological stress score.
struct VivordoPlanningService {
  private let healthStore: VivordoSnapshotStore
  private let calendarStore: VivordoCalendarSnapshotStore
  private let calendar: Calendar

  init(
    healthStore: VivordoSnapshotStore = VivordoSnapshotStore(),
    calendarStore: VivordoCalendarSnapshotStore = VivordoCalendarSnapshotStore(),
    calendar: Calendar = .autoupdatingCurrent
  ) {
    self.healthStore = healthStore
    self.calendarStore = calendarStore
    self.calendar = calendar
  }

  func answer(for query: VivordoPlanningQuery, now: Date = .now) -> VivordoPlanningAnswer {
    let calendarSnapshot: VivordoCalendarSnapshot
    do {
      calendarSnapshot = try calendarStore.load()
    } catch {
      return unavailable("Open Vivordo to connect and refresh your calendar.")
    }
    guard calendarStore.isFresh(
      calendarSnapshot,
      now: now,
      maximumAge: VivordoCalendarQueryService.maximumSnapshotAge
    ) else {
      return unavailable("Your Vivordo calendar needs a refresh. Open the app to update it.")
    }

    let healthSnapshot = freshHealthSnapshot(now: now)
    switch query {
    case .scheduleLoad:
      return scheduleLoadAnswer(
        events: calendarSnapshot.events,
        health: healthSnapshot,
        now: now
      )
    case .recoveryWindow:
      return recoveryWindowAnswer(
        events: calendarSnapshot.events,
        health: healthSnapshot,
        now: now
      )
    }
  }

  private func freshHealthSnapshot(now: Date) -> VivordoSiriSnapshot? {
    guard let snapshot = try? healthStore.load(),
          healthStore.isFresh(
            snapshot,
            now: now,
            maximumAge: VivordoSiriQueryService.maximumSnapshotAge
          ) else { return nil }
    return snapshot
  }

  private func scheduleLoadAnswer(
    events: [VivordoCalendarEvent],
    health: VivordoSiriSnapshot?,
    now: Date
  ) -> VivordoPlanningAnswer {
    let remaining = remainingTimedEvents(events, now: now)
    let todayEvents = eventsForToday(events, now: now)
    guard !remaining.isEmpty else {
      return VivordoPlanningAnswer(
        dialog: "Your remaining schedule is clear today in Vivordo.",
        title: "Schedule Load",
        headline: "Clear",
        detail: "No timed events remaining today",
        drivers: healthDrivers(health),
        events: todayEvents,
        priorities: schedulePriorities(
          remaining: [],
          backToBack: 0,
          health: health
        ),
        loadScore: 0,
        recoveryWindow: nil
      )
    }

    let occupiedMinutes = remaining.reduce(0.0) { total, event in
      let effectiveStart = max(event.start, now)
      return total + max(0, event.end.timeIntervalSince(effectiveStart) / 60)
    }
    let backToBack = backToBackCount(remaining)
    var score = min(36, remaining.count * 12)
    score += min(34, Int((occupiedMinutes / 480 * 34).rounded()))
    score += min(20, backToBack * 10)

    let healthContext = healthDrivers(health)
    if let stress = health?.stressScore {
      score += stress >= 67 ? 10 : stress >= 34 ? 5 : 0
    }
    if let sleep = health?.sleepHours {
      score += sleep < 6 ? 10 : sleep < 7 ? 5 : 0
    }
    if let wellness = health?.wellnessScore {
      score += wellness < 40 ? 10 : wellness < 60 ? 5 : 0
    }
    score = min(score, 100)

    let label = score >= 67 ? "Demanding" : score >= 34 ? "Moderate" : "Light"
    var scheduleDrivers = [
      remaining.count == 1 ? "1 event remaining" : "\(remaining.count) events remaining",
      "\(Int(occupiedMinutes.rounded())) scheduled minutes",
    ]
    if backToBack > 0 {
      scheduleDrivers.append(backToBack == 1 ? "1 back-to-back transition" : "\(backToBack) back-to-back transitions")
    }
    scheduleDrivers.append(contentsOf: healthContext.prefix(2))

    let transitionText = backToBack == 0
      ? "You have no back-to-back events."
      : "You have \(backToBack) back-to-back \(backToBack == 1 ? "transition" : "transitions")."
    return VivordoPlanningAnswer(
      dialog: "Your Vivordo schedule load is \(label.lowercased()) today. You have \(remaining.count) remaining \(remaining.count == 1 ? "event" : "events") and \(Int(occupiedMinutes.rounded())) scheduled minutes. \(transitionText)",
      title: "Schedule Load",
      headline: label,
      detail: "Calendar load \(score) out of 100",
      drivers: scheduleDrivers,
      events: todayEvents,
      priorities: schedulePriorities(
        remaining: remaining,
        backToBack: backToBack,
        health: health
      ),
      loadScore: score,
      recoveryWindow: nil
    )
  }

  private func recoveryWindowAnswer(
    events: [VivordoCalendarEvent],
    health: VivordoSiriSnapshot?,
    now: Date
  ) -> VivordoPlanningAnswer {
    let duration: TimeInterval = 30 * 60
    let startOfDay = calendar.startOfDay(for: now)
    let dayEnd = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: startOfDay) ?? now
    let searchStart = roundUpToQuarterHour(now)
    guard searchStart.addingTimeInterval(duration) <= dayEnd else {
      return noRecoveryWindow(health: health)
    }

    let busy = mergedBusyIntervals(
      remainingTimedEvents(events, now: now),
      lowerBound: searchStart,
      upperBound: dayEnd
    )
    var candidate = searchStart
    var found: VivordoRecoveryWindow?
    for interval in busy {
      if candidate.addingTimeInterval(duration) <= interval.start {
        found = VivordoRecoveryWindow(
          start: candidate,
          end: candidate.addingTimeInterval(duration)
        )
        break
      }
      candidate = max(candidate, interval.end)
    }
    if found == nil, candidate.addingTimeInterval(duration) <= dayEnd {
      found = VivordoRecoveryWindow(
        start: candidate,
        end: candidate.addingTimeInterval(duration)
      )
    }
    guard let window = found else { return noRecoveryWindow(health: health) }

    let timeRange = "\(timeText(window.start)) to \(timeText(window.end))"
    let healthContext = healthDrivers(health)
    let reason = healthContext.first.map { " \($0)." } ?? ""
    return VivordoPlanningAnswer(
      dialog: "You have a 30 minute recovery window from \(timeRange) today.\(reason)",
      title: "Recovery Window",
      headline: timeRange,
      detail: "30 minutes available today",
      drivers: healthContext,
      events: [],
      priorities: [],
      loadScore: nil,
      recoveryWindow: window
    )
  }

  private func noRecoveryWindow(health: VivordoSiriSnapshot?) -> VivordoPlanningAnswer {
    VivordoPlanningAnswer(
      dialog: "Vivordo couldn't find a free 30 minute recovery window before 8 PM today.",
      title: "Recovery Window",
      headline: "No 30-minute opening",
      detail: "Your schedule is full through 8 PM",
      drivers: healthDrivers(health),
      events: [],
      priorities: [],
      loadScore: nil,
      recoveryWindow: nil
    )
  }

  private func unavailable(_ dialog: String) -> VivordoPlanningAnswer {
    VivordoPlanningAnswer(
      dialog: dialog,
      title: "Vivordo Planning",
      headline: "Refresh needed",
      detail: "Open Vivordo to update your schedule.",
      drivers: [],
      events: [],
      priorities: [],
      loadScore: nil,
      recoveryWindow: nil
    )
  }

  private func remainingTimedEvents(
    _ events: [VivordoCalendarEvent],
    now: Date
  ) -> [VivordoCalendarEvent] {
    events.filter {
      !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: now) && $0.end > now
    }
    .sorted { $0.start < $1.start }
  }

  private func eventsForToday(
    _ events: [VivordoCalendarEvent],
    now: Date
  ) -> [VivordoCalendarEvent] {
    events.filter { calendar.isDate($0.start, inSameDayAs: now) }
      .sorted { lhs, rhs in
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        return lhs.start < rhs.start
      }
  }

  private func schedulePriorities(
    remaining: [VivordoCalendarEvent],
    backToBack: Int,
    health: VivordoSiriSnapshot?
  ) -> [String] {
    var priorities: [String] = []
    if let next = remaining.first {
      priorities.append("Prepare for \(next.title)")
    }

    let recoveryIsImportant =
      (health?.stressScore ?? 0) >= 67 ||
      (health?.sleepHours ?? 24) < 7 ||
      (health?.wellnessScore ?? 100) < 60
    if recoveryIsImportant {
      priorities.append("Protect time for recovery")
    } else if !remaining.isEmpty {
      priorities.append("Protect your open focus time")
    } else {
      priorities.append("Keep the rest of the day flexible")
    }

    if backToBack > 0 {
      priorities.append("Create a buffer between meetings")
    }
    return Array(priorities.prefix(3))
  }

  private func backToBackCount(_ events: [VivordoCalendarEvent]) -> Int {
    guard events.count > 1 else { return 0 }
    return zip(events, events.dropFirst()).reduce(0) { count, pair in
      let gap = pair.1.start.timeIntervalSince(pair.0.end)
      return count + (gap <= 15 * 60 ? 1 : 0)
    }
  }

  private func healthDrivers(_ health: VivordoSiriSnapshot?) -> [String] {
    guard let health else { return [] }
    var drivers: [String] = []
    if let stress = health.stressScore, stress >= 67 {
      drivers.append("Stress is elevated at \(stress)")
    }
    if let sleep = health.sleepHours, sleep < 7 {
      drivers.append("Sleep was \(shortHoursText(sleep))")
    }
    if let wellness = health.wellnessScore, wellness < 60 {
      drivers.append("Wellness is \(wellness)")
    }
    return drivers
  }

  private func shortHoursText(_ hours: Double) -> String {
    let totalMinutes = Int((hours * 60).rounded())
    return "\(totalMinutes / 60) hr \(totalMinutes % 60) min"
  }

  private func roundUpToQuarterHour(_ date: Date) -> Date {
    let startOfDay = calendar.startOfDay(for: date)
    let seconds = max(0, date.timeIntervalSince(startOfDay))
    let rounded = ceil(seconds / (15 * 60)) * (15 * 60)
    return startOfDay.addingTimeInterval(rounded)
  }

  private func mergedBusyIntervals(
    _ events: [VivordoCalendarEvent],
    lowerBound: Date,
    upperBound: Date
  ) -> [VivordoRecoveryWindow] {
    let intervals = events.compactMap { event -> VivordoRecoveryWindow? in
      let start = max(event.start, lowerBound)
      let end = min(event.end, upperBound)
      guard end > start else { return nil }
      return VivordoRecoveryWindow(start: start, end: end)
    }
    var merged: [VivordoRecoveryWindow] = []
    for interval in intervals {
      if let last = merged.last, interval.start <= last.end {
        merged[merged.count - 1] = VivordoRecoveryWindow(
          start: last.start,
          end: max(last.end, interval.end)
        )
      } else {
        merged.append(interval)
      }
    }
    return merged
  }

  private func timeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }
}

struct VivordoPlanningSnippetView: View {
  let answer: VivordoPlanningAnswer

  private let accent = Color(red: 0.49, green: 0.32, blue: 0.96)

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(answer.title, systemImage: answer.recoveryWindow == nil ? "chart.bar.fill" : "leaf.fill")
        .font(.headline)
        .foregroundStyle(.secondary)

      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(answer.headline)
            .font(.title2.bold())
          Text(answer.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if let score = answer.loadScore {
          ZStack {
            Circle().stroke(accent.opacity(0.18), lineWidth: 7)
            Circle()
              .trim(from: 0, to: Double(score) / 100)
              .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text("\(score)")
              .font(.headline.monospacedDigit())
          }
          .frame(width: 58, height: 58)
          .accessibilityHidden(true)
        }
      }

      if !answer.drivers.isEmpty {
        VStack(alignment: .leading, spacing: 7) {
          ForEach(answer.drivers.prefix(4), id: \.self) { driver in
            Label(driver, systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.secondary)
              .symbolRenderingMode(.hierarchical)
          }
        }
      }

      if !answer.events.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text("TODAY'S EVENTS")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

          ForEach(answer.events.prefix(5)) { event in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(accent)
                .frame(width: 58, alignment: .leading)
              Text(event.title)
                .font(.caption)
                .lineLimit(1)
            }
          }

          if answer.events.count > 5 {
            Text("+ \(answer.events.count - 5) more")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if !answer.priorities.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Text("PRIORITIES FOR TODAY")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

          ForEach(Array(answer.priorities.enumerated()), id: \.offset) { index, priority in
            HStack(alignment: .firstTextBaseline, spacing: 9) {
              Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(accent, in: Circle())
              Text(priority)
                .font(.caption)
            }
          }
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(answer.dialog)
  }
}

private protocol VivordoPlanningIntent: AppIntent {
  static var query: VivordoPlanningQuery { get }
}

private extension VivordoPlanningIntent {
  func planningResult() -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    let answer = VivordoPlanningService().answer(for: Self.query)
    return .result(
      dialog: IntentDialog(stringLiteral: answer.dialog),
      view: VivordoPlanningSnippetView(answer: answer)
    )
  }
}

struct AnalyzeScheduleLoadIntent: VivordoPlanningIntent {
  static var title: LocalizedStringResource = "Analyze Schedule Load"
  static var description = IntentDescription("Relate today's schedule density to your current Vivordo health context.")
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let query = VivordoPlanningQuery.scheduleLoad

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    planningResult()
  }
}

struct FindRecoveryWindowIntent: VivordoPlanningIntent {
  static var title: LocalizedStringResource = "Find Recovery Window"
  static var description = IntentDescription("Find a free 30-minute recovery window in today's Vivordo schedule.")
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
  static let query = VivordoPlanningQuery.recoveryWindow

  func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
    planningResult()
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
    AppShortcut(
      intent: GetTodayScheduleIntent(),
      phrases: [
        "What's on my schedule today in \(.applicationName)",
        "What's my schedule on \(.applicationName)",
        "What's my schedule in \(.applicationName)",
        "What's my schedule for today on \(.applicationName)",
        "What do I have today in \(.applicationName)",
        "Tell me my schedule on \(.applicationName)",
        "Tell me today's events from \(.applicationName)",
        "Show my \(.applicationName) schedule today"
      ],
      shortTitle: "Today's Schedule",
      systemImageName: "calendar"
    )
    AppShortcut(
      intent: GetNextCalendarEventIntent(),
      phrases: [
        "What's next on my calendar in \(.applicationName)",
        "What's my next event in \(.applicationName)",
        "Tell me my next event from \(.applicationName)",
        "Show my next \(.applicationName) event"
      ],
      shortTitle: "Next Event",
      systemImageName: "calendar.badge.clock"
    )
    AppShortcut(
      intent: AnalyzeScheduleLoadIntent(),
      phrases: [
        "How stressful is my schedule in \(.applicationName)",
        "How busy is my schedule in \(.applicationName)",
        "How busy is my \(.applicationName) schedule",
        "How packed is my schedule in \(.applicationName)",
        "How hectic is my day in \(.applicationName)",
        "How full is my \(.applicationName) schedule today",
        "Is my \(.applicationName) schedule busy today",
        "How demanding is my day in \(.applicationName)",
        "Analyze my schedule with \(.applicationName)",
        "What's my schedule load in \(.applicationName)"
      ],
      shortTitle: "Schedule Load",
      systemImageName: "chart.bar.fill"
    )
    AppShortcut(
      intent: FindRecoveryWindowIntent(),
      phrases: [
        "Find me a recovery break in \(.applicationName)",
        "When can I take a break with \(.applicationName)",
        "Find a free wellness break in \(.applicationName)",
        "Where can I fit a break in \(.applicationName)"
      ],
      shortTitle: "Recovery Window",
      systemImageName: "leaf.fill"
    )
  }
}
