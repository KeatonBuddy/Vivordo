import AppIntents
import SwiftUI
import WidgetKit

@main
struct VivordoLiveActivitiesBundle: WidgetBundle {
  var body: some Widget {
    StressScoreWidget()
    WellnessScoreWidget()
    FitnessRingWidget()
    CalendarWidget()
    WorkoutLiveActivity()
  }
}

private enum VivordoWidgetData {
  static let suite = "group.com.vivordo.health"

  static var defaults: UserDefaults {
    UserDefaults(suiteName: suite) ?? .standard
  }

  static func number(_ key: String, fallback: Double) -> Double {
    guard defaults.object(forKey: key) != nil else { return fallback }
    return defaults.double(forKey: key)
  }

  static func integer(_ key: String, fallback: Int) -> Int {
    guard defaults.object(forKey: key) != nil else { return fallback }
    return defaults.integer(forKey: key)
  }
}

private struct VivordoWidgetEntry: TimelineEntry {
  let date: Date
  let stress: Int
  let wellness: Int
  let wellnessDelta: Int
  let steps: Int
  let stepsGoal: Int
  let calories: Int
  let caloriesGoal: Int
  let exerciseMinutes: Int
  let exerciseGoal: Int

  static func current(date: Date = .now) -> VivordoWidgetEntry {
    VivordoWidgetEntry(
      date: date,
      stress: VivordoWidgetData.integer("stressScore", fallback: 0),
      wellness: VivordoWidgetData.integer("wellnessScore", fallback: 0),
      wellnessDelta: VivordoWidgetData.integer("wellnessDelta", fallback: 0),
      steps: VivordoWidgetData.integer("steps", fallback: 0),
      stepsGoal: max(VivordoWidgetData.integer("stepsGoal", fallback: 10_000), 1),
      calories: VivordoWidgetData.integer("activeCalories", fallback: 0),
      caloriesGoal: max(VivordoWidgetData.integer("activeCaloriesGoal", fallback: 700), 1),
      exerciseMinutes: VivordoWidgetData.integer("exerciseMinutes", fallback: 0),
      exerciseGoal: max(VivordoWidgetData.integer("exerciseGoal", fallback: 40), 1)
    )
  }
}

private struct VivordoWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> VivordoWidgetEntry {
    VivordoWidgetEntry(
      date: .now,
      stress: 34,
      wellness: 82,
      wellnessDelta: 6,
      steps: 7_200,
      stepsGoal: 10_000,
      calories: 420,
      caloriesGoal: 700,
      exerciseMinutes: 28,
      exerciseGoal: 40
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (VivordoWidgetEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : .current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<VivordoWidgetEntry>) -> Void) {
    let entry = VivordoWidgetEntry.current()
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
  }
}

private enum VivordoWidgetPalette {
  static let purple = Color(red: 0.34, green: 0.26, blue: 0.93)
  static let darkModePurple = Color(red: 0.69, green: 0.62, blue: 1.00)
  static let blue = Color(red: 0.20, green: 0.45, blue: 0.98)
  static let coral = Color(red: 1.00, green: 0.39, blue: 0.36)
  static let mint = Color(red: 0.31, green: 0.82, blue: 0.68)
  static let ink = Color.primary
  static let secondary = Color.secondary
  static let track = Color.primary.opacity(0.10)
}

private struct VivordoWidgetBackground: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      if colorScheme == .dark {
        Color(red: 0.055, green: 0.050, blue: 0.085)
      } else {
        Color.white
      }
      RadialGradient(
        colors: [
          (colorScheme == .dark
            ? VivordoWidgetPalette.darkModePurple.opacity(0.20)
            : VivordoWidgetPalette.purple.opacity(0.08)),
          .clear,
        ],
        center: .topLeading,
        startRadius: 4,
        endRadius: 220
      )
    }
  }
}

private struct VivordoBrand: View {
  @Environment(\.colorScheme) private var colorScheme

  var compact = false

  private var brandPrimary: Color {
    colorScheme == .dark
      ? VivordoWidgetPalette.darkModePurple
      : Color(red: 0.20, green: 0.12, blue: 0.43)
  }

  private var brandSecondary: Color {
    colorScheme == .dark
      ? Color(red: 0.48, green: 0.39, blue: 0.82)
      : Color(red: 0.46, green: 0.35, blue: 0.72)
  }

  var body: some View {
    HStack(spacing: compact ? 5 : 7) {
      VivordoMark()
        .fill(
          LinearGradient(
            colors: [brandSecondary, brandPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: compact ? 24 : 30, height: compact ? 22 : 27)
      Text("vivordo")
        .font(.system(size: compact ? 17 : 21, weight: .medium, design: .rounded))
        .tracking(compact ? 2.2 : 2.8)
        .foregroundStyle(brandPrimary)
    }
  }
}

private struct VivordoMark: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.width * 0.49, y: rect.height * 0.90))
    path.addCurve(
      to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.06),
      control1: CGPoint(x: rect.width * 0.18, y: rect.height * 0.72),
      control2: CGPoint(x: rect.width * 0.12, y: rect.height * 0.28)
    )
    path.addCurve(
      to: CGPoint(x: rect.width * 0.60, y: rect.height * 0.82),
      control1: CGPoint(x: rect.width * 0.45, y: rect.height * 0.14),
      control2: CGPoint(x: rect.width * 0.39, y: rect.height * 0.65)
    )
    path.addCurve(
      to: CGPoint(x: rect.width * 0.49, y: rect.height * 0.90),
      control1: CGPoint(x: rect.width * 0.57, y: rect.height * 0.86),
      control2: CGPoint(x: rect.width * 0.54, y: rect.height * 0.89)
    )
    path.closeSubpath()

    path.move(to: CGPoint(x: rect.width * 0.54, y: rect.height * 0.60))
    path.addCurve(
      to: CGPoint(x: rect.width * 0.96, y: rect.height * 0.06),
      control1: CGPoint(x: rect.width * 0.60, y: rect.height * 0.25),
      control2: CGPoint(x: rect.width * 0.81, y: rect.height * 0.08)
    )
    path.addCurve(
      to: CGPoint(x: rect.width * 0.54, y: rect.height * 0.60),
      control1: CGPoint(x: rect.width * 0.98, y: rect.height * 0.37),
      control2: CGPoint(x: rect.width * 0.72, y: rect.height * 0.69)
    )
    path.closeSubpath()
    return path
  }
}

private struct ScoreRing: View {
  let progress: Double
  let colors: [Color]
  let lineWidth: CGFloat
  var gapDegrees: Double = 35

  var body: some View {
    ZStack {
      Circle()
        .trim(from: gapDegrees / 720, to: 1 - gapDegrees / 720)
        .stroke(VivordoWidgetPalette.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      Circle()
        .trim(from: gapDegrees / 720, to: gapDegrees / 720 + (1 - gapDegrees / 360) * min(max(progress, 0), 1))
        .stroke(
          AngularGradient(colors: colors, center: .center),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }
    .rotationEffect(.degrees(90 + gapDegrees / 2))
  }
}

private struct WidgetScoreView: View {
  @Environment(\.colorScheme) private var colorScheme

  let title: String
  let score: Int
  let status: String
  let detail: String
  let stressStyle: Bool

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.height < 200
      VStack(spacing: compact ? 5 : 8) {
        VivordoBrand(compact: compact)
        Text(title)
          .font(.system(size: compact ? 11 : 14, weight: .semibold))
          .tracking(compact ? 1.4 : 2.0)
          .foregroundStyle(VivordoWidgetPalette.secondary)
          .lineLimit(1)
        ZStack {
          ScoreRing(
            progress: Double(score) / 100,
            colors: stressStyle
              ? [VivordoWidgetPalette.purple, VivordoWidgetPalette.blue]
              : [VivordoWidgetPalette.purple, Color(red: 0.42, green: 0.32, blue: 1.0)],
            lineWidth: compact ? 8 : 12,
            gapDegrees: stressStyle ? 55 : 18
          )
          VStack(spacing: -2) {
            Text("\(score)")
              .font(.system(size: compact ? 32 : 48, weight: .bold, design: .rounded))
              .foregroundStyle(VivordoWidgetPalette.ink)
              .contentTransition(.numericText())
            Text("/100")
              .font(.system(size: compact ? 11 : 16, weight: .medium))
              .foregroundStyle(VivordoWidgetPalette.secondary)
          }
        }
        .frame(width: compact ? 70 : 118, height: compact ? 70 : 118)
        Text(status)
          .font(.system(size: compact ? 12 : 16, weight: .semibold, design: .rounded))
          .foregroundStyle(
            stressStyle
              ? (colorScheme == .dark ? VivordoWidgetPalette.darkModePurple : VivordoWidgetPalette.blue)
              : (colorScheme == .dark
                ? VivordoWidgetPalette.mint
                : Color(red: 0.02, green: 0.42, blue: 0.28))
          )
          .padding(.horizontal, compact ? 10 : 16)
          .padding(.vertical, compact ? 2 : 5)
          .background(
            Capsule().fill(
              stressStyle
                ? VivordoWidgetPalette.blue.opacity(0.10)
                : VivordoWidgetPalette.mint.opacity(0.22)
            )
          )
        Text(detail)
          .font(.system(size: compact ? 10 : 14, weight: .medium))
          .foregroundStyle(VivordoWidgetPalette.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(compact ? 7 : 12)
    }
  }
}

private struct StressScoreWidgetView: View {
  let entry: VivordoWidgetEntry

  private var label: String {
    switch entry.stress {
    case ..<30: return "Very low"
    case ..<60: return "Low"
    case ..<80: return "Moderate"
    default: return "High"
    }
  }

  private var detail: String {
    switch entry.stress {
    case ..<60: return "Calm range"
    case ..<80: return "Watch your stress"
    default: return "Take time to reset"
    }
  }

  var body: some View {
    WidgetScoreView(title: "STRESS SCORE", score: entry.stress, status: label, detail: detail, stressStyle: true)
      .widgetURL(URL(string: "com.vivordo.health://widget/home"))
  }
}

private struct WellnessScoreWidgetView: View {
  let entry: VivordoWidgetEntry

  private var label: String {
    switch entry.wellness {
    case ..<40: return "Needs attention"
    case ..<60: return "Fair"
    case ..<80: return "Good"
    default: return "Excellent"
    }
  }

  private var detail: String {
    if entry.wellnessDelta == 0 { return "Updated today" }
    return entry.wellnessDelta > 0
      ? "↗ Up \(entry.wellnessDelta) today"
      : "↘ Down \(abs(entry.wellnessDelta)) today"
  }

  var body: some View {
    WidgetScoreView(title: "WELLNESS SCORE", score: entry.wellness, status: label, detail: detail, stressStyle: false)
      .widgetURL(URL(string: "com.vivordo.health://widget/wellness"))
  }
}

private struct FitnessRingWidgetView: View {
  @Environment(\.colorScheme) private var colorScheme

  let entry: VivordoWidgetEntry

  private var stepsProgress: Double { Double(entry.steps) / Double(entry.stepsGoal) }
  private var calorieProgress: Double { Double(entry.calories) / Double(entry.caloriesGoal) }
  private var exerciseProgress: Double { Double(entry.exerciseMinutes) / Double(entry.exerciseGoal) }
  private var overall: Int {
    let cappedSteps = min(stepsProgress, 1.0)
    let cappedCalories = min(calorieProgress, 1.0)
    let cappedExercise = min(exerciseProgress, 1.0)
    let average = (cappedSteps + cappedCalories + cappedExercise) / 3.0
    return Int((average * 100.0).rounded())
  }

  var body: some View {
    GeometryReader { proxy in
      let compact = proxy.size.height < 200
      VStack(spacing: compact ? 6 : 9) {
        VivordoBrand(compact: compact)
        Text("TODAY’S FITNESS")
          .font(.system(size: compact ? 11 : 14, weight: .semibold))
          .tracking(compact ? 1.3 : 1.9)
          .foregroundStyle(VivordoWidgetPalette.secondary)
        ZStack {
          FitnessArc(progress: stepsProgress, color: VivordoWidgetPalette.purple, lineWidth: compact ? 8 : 11)
            .padding(0)
          FitnessArc(progress: calorieProgress, color: VivordoWidgetPalette.coral, lineWidth: compact ? 8 : 11)
            .padding(compact ? 13 : 20)
          FitnessArc(progress: exerciseProgress, color: VivordoWidgetPalette.mint, lineWidth: compact ? 8 : 11)
            .padding(compact ? 26 : 40)
          Text("\(overall)%")
            .font(.system(size: compact ? 23 : 32, weight: .bold, design: .rounded))
            .foregroundStyle(
              colorScheme == .dark
                ? VivordoWidgetPalette.darkModePurple
                : Color(red: 0.20, green: 0.12, blue: 0.43)
            )
        }
        .frame(width: compact ? 82 : 138, height: compact ? 82 : 138)
        Text("\(entry.calories) cal · \(entry.exerciseMinutes) min")
          .font(.system(size: compact ? 12 : 16, weight: .semibold))
          .foregroundStyle(VivordoWidgetPalette.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(compact ? 7 : 12)
    }
    .widgetURL(URL(string: "com.vivordo.health://widget/fitness"))
  }
}

private struct FitnessArc: View {
  let progress: Double
  let color: Color
  let lineWidth: CGFloat

  var body: some View {
    ZStack {
      Circle().stroke(color.opacity(0.10), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: min(max(progress, 0), 1))
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
  }
}

private struct VivordoCalendarEvent: Identifiable {
  let title: String
  let start: Date
  let end: Date
  let isAllDay: Bool
  let kind: String

  var id: String { "\(title)|\(start.timeIntervalSince1970)" }

  static func current() -> [VivordoCalendarEvent] {
    guard let rawEvents = VivordoWidgetData.defaults.array(forKey: "calendarEvents") as? [[String: Any]] else {
      return []
    }
    return rawEvents.compactMap { raw in
      guard let title = raw["title"] as? String,
            let startValue = raw["startAt"] as? NSNumber else {
        return nil
      }
      let endValue = raw["endAt"] as? NSNumber
      let start = Date(timeIntervalSince1970: startValue.doubleValue / 1_000)
      let end = Date(timeIntervalSince1970: (endValue?.doubleValue ?? startValue.doubleValue) / 1_000)
      return VivordoCalendarEvent(
        title: title,
        start: start,
        end: end,
        isAllDay: raw["isAllDay"] as? Bool ?? false,
        kind: raw["kind"] as? String ?? "calendar"
      )
    }
    .sorted { $0.start < $1.start }
  }
}

private enum VivordoCalendarDates {
  static var calendar: Calendar { Calendar.autoupdatingCurrent }

  static func dayKey(for date: Date) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  static func currentWeek(now: Date = .now) -> [Date] {
    let startOfToday = calendar.startOfDay(for: now)
    let weekday = calendar.component(.weekday, from: startOfToday)
    let daysFromMonday = (weekday + 5) % 7
    let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfToday) ?? startOfToday
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
  }
}

struct SelectVivordoCalendarDayIntent: AppIntent {
  static var title: LocalizedStringResource = "Select calendar day"
  static var description = IntentDescription("Shows events for the selected day in the Vivordo calendar widget.")
  static var openAppWhenRun = false

  @Parameter(title: "Day")
  var dayKey: String

  init() {}

  init(dayKey: String) {
    self.dayKey = dayKey
  }

  func perform() async throws -> some IntentResult {
    VivordoWidgetData.defaults.set(dayKey, forKey: "calendarSelectedDay")
    VivordoWidgetData.defaults.set(Date().timeIntervalSince1970, forKey: "calendarSelectedAt")
    WidgetCenter.shared.reloadTimelines(ofKind: "VivordoCalendar")
    return .result()
  }
}

private struct VivordoCalendarEntry: TimelineEntry {
  let date: Date
  let weekDates: [Date]
  let selectedDate: Date
  let events: [VivordoCalendarEvent]

  static func current(date: Date = .now) -> VivordoCalendarEntry {
    let weekDates = VivordoCalendarDates.currentWeek(now: date)
    let selectedKey = VivordoWidgetData.defaults.string(forKey: "calendarSelectedDay")
    let selectedDate = weekDates.first {
      VivordoCalendarDates.dayKey(for: $0) == selectedKey
    } ?? VivordoCalendarDates.calendar.startOfDay(for: date)
    return VivordoCalendarEntry(
      date: date,
      weekDates: weekDates,
      selectedDate: selectedDate,
      events: VivordoCalendarEvent.current()
    )
  }

  var selectedEvents: [VivordoCalendarEvent] {
    events.filter { VivordoCalendarDates.calendar.isDate($0.start, inSameDayAs: selectedDate) }
  }
}

private struct VivordoCalendarProvider: TimelineProvider {
  func placeholder(in context: Context) -> VivordoCalendarEntry {
    let now = Date.now
    let calendar = VivordoCalendarDates.calendar
    let morning = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now) ?? now
    let meeting = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
    return VivordoCalendarEntry(
      date: now,
      weekDates: VivordoCalendarDates.currentWeek(now: now),
      selectedDate: calendar.startOfDay(for: now),
      events: [
        VivordoCalendarEvent(
          title: "Morning Run",
          start: morning,
          end: morning.addingTimeInterval(45 * 60),
          isAllDay: false,
          kind: "running"
        ),
        VivordoCalendarEvent(
          title: "Team Meeting",
          start: meeting,
          end: meeting.addingTimeInterval(60 * 60),
          isAllDay: false,
          kind: "calendar"
        ),
      ]
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (VivordoCalendarEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : .current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<VivordoCalendarEntry>) -> Void) {
    let entry = VivordoCalendarEntry.current()
    let nextRefresh = VivordoCalendarDates.calendar.date(
      byAdding: .minute,
      value: 15,
      to: .now
    ) ?? .now.addingTimeInterval(15 * 60)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }
}

private struct CalendarWidgetView: View {
  @Environment(\.colorScheme) private var colorScheme

  let entry: VivordoCalendarEntry

  private var eventSurface: Color {
    colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.72)
  }

  private var isToday: Bool {
    VivordoCalendarDates.calendar.isDateInToday(entry.selectedDate)
  }

  private var selectedDateTitle: String {
    entry.selectedDate.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day()
    ).uppercased()
  }

  private var eventsTitle: String {
    if isToday { return "TODAY’S EVENTS" }
    let weekday = entry.selectedDate.formatted(.dateTime.weekday(.wide)).uppercased()
    return "\(weekday)’S EVENTS"
  }

  var body: some View {
    GeometryReader { proxy in
      let contentWidth = max(proxy.size.width - 24, 0)
      VStack(spacing: 8) {
        HStack(alignment: .top) {
          VivordoBrand()
          Spacer()
          VStack(alignment: .trailing, spacing: 0) {
            Text(isToday ? "TODAY" : "SELECTED")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(VivordoWidgetPalette.secondary)
            Text(selectedDateTitle)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(VivordoWidgetPalette.ink)
              .lineLimit(1)
          }
        }

        HStack(alignment: .center, spacing: 10) {
          daySelector
            .frame(width: contentWidth * 0.46)
          eventsPanel
            .frame(width: max(contentWidth * 0.54 - 10, 0))
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }

  private var daySelector: some View {
    HStack(spacing: 0) {
      ForEach(entry.weekDates, id: \.self) { day in
        let selected = VivordoCalendarDates.calendar.isDate(day, inSameDayAs: entry.selectedDate)
        Button(intent: SelectVivordoCalendarDayIntent(dayKey: VivordoCalendarDates.dayKey(for: day))) {
          VStack(spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(VivordoWidgetPalette.secondary)
            Text(day.formatted(.dateTime.day()))
              .font(.system(size: 14, weight: selected ? .bold : .semibold))
              .foregroundStyle(selected ? Color.white : VivordoWidgetPalette.ink)
              .frame(height: 29)
              .background {
                if selected {
                  Circle()
                    .fill(VivordoWidgetPalette.purple)
                    .frame(width: 27, height: 27)
                }
              }
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var eventsPanel: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(eventsTitle)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(VivordoWidgetPalette.secondary)
        .lineLimit(1)

      if entry.selectedEvents.isEmpty {
        HStack(spacing: 7) {
          calendarIcon(symbol: "calendar", color: VivordoWidgetPalette.purple)
          Text("No events scheduled")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(VivordoWidgetPalette.ink)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .padding(.horizontal, 8)
        .background(eventSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VivordoWidgetPalette.track, lineWidth: 0.7))
      } else {
        ForEach(Array(entry.selectedEvents.prefix(2))) { event in
          eventRow(event)
        }
      }

      Spacer(minLength: 1)

      Link(destination: URL(string: "com.vivordo.health://widget/calendar")!) {
        HStack(spacing: 2) {
          Spacer()
          Text("View Calendar")
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(VivordoWidgetPalette.purple)
      }
    }
  }

  private func eventRow(_ event: VivordoCalendarEvent) -> some View {
    HStack(spacing: 7) {
      let presentation = iconPresentation(for: event.kind)
      calendarIcon(symbol: presentation.symbol, color: presentation.color)
      Text(event.title)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(VivordoWidgetPalette.ink)
        .lineLimit(1)
      Spacer(minLength: 3)
      Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(VivordoWidgetPalette.secondary)
        .lineLimit(1)
    }
    .frame(height: 36)
    .padding(.horizontal, 8)
    .background(eventSurface, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VivordoWidgetPalette.track, lineWidth: 0.7))
  }

  private func calendarIcon(symbol: String, color: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(color)
      .frame(width: 28, height: 28)
      .background(color.opacity(0.10), in: Circle())
  }

  private func iconPresentation(for kind: String) -> (symbol: String, color: Color) {
    switch kind {
    case "running": return ("figure.run", Color.orange)
    case "fitness": return ("dumbbell.fill", VivordoWidgetPalette.coral)
    case "sport": return ("sportscourt.fill", VivordoWidgetPalette.mint)
    default: return ("calendar", VivordoWidgetPalette.purple)
    }
  }
}

private struct StressScoreWidget: Widget {
  let kind = "VivordoStressScore"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: VivordoWidgetProvider()) { entry in
      StressScoreWidgetView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
    }
    .configurationDisplayName("Stress Score")
    .description("See your latest Vivordo stress score at a glance.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

private struct WellnessScoreWidget: Widget {
  let kind = "VivordoWellnessScore"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: VivordoWidgetProvider()) { entry in
      WellnessScoreWidgetView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
    }
    .configurationDisplayName("Wellness Score")
    .description("Keep your daily Vivordo wellness score close by.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

private struct FitnessRingWidget: Widget {
  let kind = "VivordoFitnessRings"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: VivordoWidgetProvider()) { entry in
      FitnessRingWidgetView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
    }
    .configurationDisplayName("Today’s Fitness")
    .description("Track steps, active calories, and exercise progress.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

private struct CalendarWidget: Widget {
  let kind = "VivordoCalendar"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: VivordoCalendarProvider()) { entry in
      CalendarWidgetView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
    }
    .configurationDisplayName("Weekly Calendar")
    .description("See this week’s events and switch days without opening Vivordo.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
