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
    TodayAgendaWidget()
    if #available(iOS 27.0, *) {
      DayDashboardWidget()
    }
    WorkoutLiveActivity()
  }
}

private enum VivordoWidgetData {
  static let suite = "group.com.vivordo.health"
  static let defaults: UserDefaults = UserDefaults(suiteName: suite) ?? .standard

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
  // False when the app has not published today, so yesterday's numbers and
  // "no reading" zeros are not shown as today's values.
  let hasMetrics: Bool
  let hasStress: Bool
  let hasWellness: Bool
  let updatedAt: Date?

  static func current(date: Date = .now) -> VivordoWidgetEntry {
    let defaults = VivordoWidgetData.defaults
    let fresh = defaults.string(forKey: "dashboardMetricsDay") == VivordoCalendarDates.dayKey(for: date)
    return VivordoWidgetEntry(
      date: date,
      stress: VivordoWidgetData.integer("stressScore", fallback: 0),
      wellness: VivordoWidgetData.integer("wellnessScore", fallback: 0),
      wellnessDelta: VivordoWidgetData.integer("wellnessDelta", fallback: 0),
      steps: VivordoWidgetData.integer("steps", fallback: 0),
      stepsGoal: max(VivordoWidgetData.integer("stepsGoal", fallback: 10_000), 1),
      calories: VivordoWidgetData.integer("activeCalories", fallback: 0),
      caloriesGoal: max(VivordoWidgetData.integer("activeCaloriesGoal", fallback: 700), 1),
      exerciseMinutes: VivordoWidgetData.integer("exerciseMinutes", fallback: 0),
      exerciseGoal: max(VivordoWidgetData.integer("exerciseGoal", fallback: 40), 1),
      hasMetrics: fresh,
      hasStress: fresh && defaults.bool(forKey: "dashboardHasStress"),
      // Builds before this flag existed never wrote it; their scores were real.
      hasWellness: fresh && (defaults.object(forKey: "dashboardHasWellness") as? Bool ?? true),
      updatedAt: defaults.double(forKey: "dashboardMetricsUpdatedAt") > 0
        ? Date(timeIntervalSince1970: defaults.double(forKey: "dashboardMetricsUpdatedAt") / 1_000)
        : nil
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
      exerciseGoal: 40,
      hasMetrics: true,
      hasStress: true,
      hasWellness: true,
      updatedAt: .now
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (VivordoWidgetEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : .current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<VivordoWidgetEntry>) -> Void) {
    // The midnight entry blanks yesterday's numbers even if no reload runs.
    let now = Date.now
    let midnight = VivordoCalendarDates.calendar.date(
      byAdding: .day, value: 1, to: VivordoCalendarDates.calendar.startOfDay(for: now)
    ) ?? now
    completion(Timeline(entries: [.current(date: now), .current(date: midnight)],
                        policy: .after(now.addingTimeInterval(15 * 60))))
  }
}

private enum VivordoWidgetPalette {
  static let purple = Color(red: 0.34, green: 0.26, blue: 0.93)
  static let darkModePurple = Color(red: 0.69, green: 0.62, blue: 1.00)
  static let blue = Color(red: 0.20, green: 0.45, blue: 0.98)
  static let coral = Color(red: 1.00, green: 0.39, blue: 0.36)
  static let mint = Color(red: 0.31, green: 0.82, blue: 0.68)
  static let amber = Color(red: 0.94, green: 0.62, blue: 0.15)
  // Brand purple, lightened in dark mode so text and marks stay legible.
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.69, green: 0.62, blue: 1.00, alpha: 1)
      : UIColor(red: 0.34, green: 0.26, blue: 0.93, alpha: 1)
  })
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

private struct VivordoMark: Shape {
  // Outline traced from the app icon (AppIcon 1024px), as x, y pairs
  // normalised to the mark's bounding box. `corners` are the sharp leaf tips;
  // every other point is a smoothing control point.
  private static let aspect: CGFloat = 1.2520
  private static let leaves: [(corners: Set<Int>, points: [CGFloat])] = [
    (
      corners: [0, 16],
      points: [
      0.0016, 0, 0.0442, 0.002, 0.0753, 0.0102, 0.1457, 0.0389, 0.2128, 0.082, 0.2848, 0.1496,
      0.3388, 0.2213, 0.3732, 0.2848, 0.4026, 0.3668, 0.4321, 0.4775, 0.4615, 0.5697, 0.4975,
      0.6537, 0.527, 0.7049, 0.5728, 0.7664, 0.6105, 0.8033, 0.653, 0.8381, 0.7447, 0.8996,
      0.7005, 0.9467, 0.6399, 0.9836, 0.5827, 1, 0.5221, 1, 0.4828, 0.9918, 0.4354, 0.9734,
      0.3764, 0.9385, 0.3322, 0.9037, 0.2586, 0.8299, 0.1849, 0.7357, 0.1277, 0.6455, 0.0917,
      0.5697, 0.0622, 0.4877, 0.054, 0.4488, 0.0475, 0.4344, 0.0262, 0.334, 0.0115, 0.2316,
      0.0098, 0.1947, 0.0049, 0.168, 0, 0.0553
      ]
    ),
    (
      corners: [1],
      points: [
      0.9771, 0, 0.9951, 0.002, 1, 0.0451, 0.9984, 0.1619, 0.9902, 0.2377, 0.9771, 0.3135,
      0.9624, 0.373, 0.9345, 0.4549, 0.9051, 0.5205, 0.8691, 0.5799, 0.8249, 0.6393, 0.7856,
      0.6844, 0.73, 0.7377, 0.7021, 0.7561, 0.6809, 0.7643, 0.6694, 0.7643, 0.6481, 0.7561,
      0.6187, 0.7377, 0.581, 0.7029, 0.5516, 0.6639, 0.5368, 0.6373, 0.527, 0.6025, 0.527,
      0.5861, 0.5368, 0.5287, 0.5581, 0.4426, 0.5794, 0.3791, 0.6105, 0.3053, 0.6465, 0.2398,
      0.6661, 0.2111, 0.7169, 0.1475, 0.7643, 0.1025, 0.7987, 0.0758, 0.8609, 0.0389, 0.9296,
      0.0102
      ]
    ),
  ]

  func path(in rect: CGRect) -> Path {
    // Aspect-fit so the mark is never stretched or slanted by its frame.
    let width = min(rect.width, rect.height * Self.aspect)
    let height = width / Self.aspect
    let originX = rect.midX - width / 2
    let originY = rect.midY - height / 2
    var path = Path()
    for leaf in Self.leaves {
      let points = stride(from: 0, to: leaf.points.count, by: 2).map {
        CGPoint(x: originX + leaf.points[$0] * width, y: originY + leaf.points[$0 + 1] * height)
      }
      let count = points.count
      func mid(_ i: Int) -> CGPoint {
        let a = points[i], b = points[(i + 1) % count]
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
      }
      path.move(to: mid(count - 1))
      for i in 0..<count {
        if leaf.corners.contains(i) {
          path.addLine(to: points[i])
          path.addLine(to: mid(i))
        } else {
          path.addQuadCurve(to: mid(i), control: points[i])
        }
      }
      path.closeSubpath()
    }
    return path
  }
}

private func vivordoTime(_ date: Date) -> String {
  date.formatted(date: .omitted, time: .shortened)
}

private func vivordoDuration(_ seconds: TimeInterval) -> String {
  let minutes = max(0, Int(seconds / 60))
  return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" : "\(minutes)m"
}

private extension VivordoWidgetEntry {
  // Same bands and labels as homeStressLevel in the app.
  var stressState: (label: String, color: Color)? {
    guard hasStress else { return nil }
    switch stress {
    case ..<30: return ("Low", VivordoWidgetPalette.mint)
    case ..<60: return ("Moderate", VivordoWidgetPalette.mint)
    case ..<80: return ("Elevated", VivordoWidgetPalette.amber)
    default: return ("High", VivordoWidgetPalette.coral)
    }
  }

  var wellnessState: (label: String, color: Color)? {
    guard hasWellness else { return nil }
    switch wellness {
    case ..<40: return ("Needs attention", VivordoWidgetPalette.coral)
    case ..<60: return ("Fair", VivordoWidgetPalette.amber)
    case ..<80: return ("Good", VivordoWidgetPalette.mint)
    default: return ("Excellent", VivordoWidgetPalette.mint)
    }
  }

  var updatedText: String {
    updatedAt.map { "Updated \(vivordoTime($0))" } ?? "Updated today"
  }
}

private struct ScoreSmallView: View {
  let title: String
  let score: Int?
  let state: (label: String, color: Color)?
  let footnote: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        Text(score.map { "\($0)" } ?? "—")
          .font(.system(size: 44, weight: .semibold, design: .rounded))
          .foregroundStyle(score == nil ? .tertiary : .primary)
          .contentTransition(.numericText())
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        if let score, let state {
          FitnessArc(progress: Double(score) / 100, color: state.color, lineWidth: 6)
            .frame(width: 42, height: 42)
        }
      }
      .padding(.top, 6)
      if let state {
        Text(state.label)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.vertical, 3)
          .background(state.color.opacity(0.22), in: Capsule())
          .padding(.top, 8)
      } else {
        Text("No reading today")
          .font(.subheadline.weight(.semibold))
          .padding(.top, 8)
      }
      Spacer(minLength: 4)
      Text(footnote)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(16)
    .accessibilityElement(children: .combine)
  }
}

private struct StressScoreWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: VivordoWidgetEntry

  private var footnote: String {
    guard entry.hasStress else { return "Open Vivordo to update" }
    return entry.stress >= 60 ? "Try a 2-minute reset" : entry.updatedText
  }

  var body: some View {
    Group {
      switch family {
      case .accessoryCircular:
        StressGaugeView(entry: entry)
      case .accessoryInline:
        Text(entry.stressState.map { "Stress \(entry.stress) · \($0.label)" } ?? "Stress —")
      default:
        ScoreSmallView(
          title: "Stress",
          score: entry.hasStress ? entry.stress : nil,
          state: entry.stressState,
          footnote: footnote
        )
      }
    }
    .widgetURL(URL(string: "com.vivordo.health://widget/home"))
  }
}

private struct StressGaugeView: View {
  let entry: VivordoWidgetEntry

  var body: some View {
    Gauge(value: Double(entry.hasStress ? entry.stress : 0), in: 0...100) {
      // The label sits in the ring's bottom gap, which only fits a glyph.
      VivordoMark()
        .fill(.primary)
        .frame(width: 14, height: 11)
        .accessibilityLabel("Stress")
    } currentValueLabel: {
      Text(entry.hasStress ? "\(entry.stress)" : "—")
    }
    .gaugeStyle(.accessoryCircular)
    .tint(entry.stressState?.color ?? .gray)
  }
}

private struct WellnessScoreWidgetView: View {
  let entry: VivordoWidgetEntry

  private var footnote: String {
    guard entry.hasWellness else { return "Open Vivordo to update" }
    if entry.wellnessDelta == 0 { return entry.updatedText }
    return entry.wellnessDelta > 0
      ? "↑ \(entry.wellnessDelta) from yesterday"
      : "↓ \(abs(entry.wellnessDelta)) from yesterday"
  }

  var body: some View {
    ScoreSmallView(
      title: "Wellness",
      score: entry.hasWellness ? entry.wellness : nil,
      state: entry.wellnessState,
      footnote: footnote
    )
    .widgetURL(URL(string: "com.vivordo.health://widget/wellness"))
  }
}

private struct ProgressBar: View {
  let progress: Double
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(color.opacity(0.15))
        Capsule()
          .fill(color)
          .frame(width: proxy.size.width * min(max(progress, 0), 1))
          .widgetAccentable()
      }
    }
    .frame(height: 5)
  }
}

private struct FitnessRingWidgetView: View {
  let entry: VivordoWidgetEntry

  private func progress(_ value: Int, _ goal: Int) -> Double {
    entry.hasMetrics ? Double(value) / Double(goal) : 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Activity")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(entry.hasMetrics ? entry.steps.formatted() : "—")
        .font(.system(size: 28, weight: .semibold, design: .rounded))
        .foregroundStyle(entry.hasMetrics ? .primary : .tertiary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(.top, 4)
      Text("of \(entry.stepsGoal.formatted()) steps")
        .font(.caption2)
        .foregroundStyle(.secondary)
      ProgressBar(progress: progress(entry.steps, entry.stepsGoal), color: VivordoWidgetPalette.purple)
        .padding(.top, 6)
      HStack {
        Text("\(entry.hasMetrics ? entry.calories : 0) / \(entry.caloriesGoal) cal")
        Spacer(minLength: 4)
        Text("\(entry.hasMetrics ? entry.exerciseMinutes : 0) / \(entry.exerciseGoal) min")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.top, 8)
      HStack(spacing: 6) {
        ProgressBar(progress: progress(entry.calories, entry.caloriesGoal), color: VivordoWidgetPalette.coral)
        ProgressBar(progress: progress(entry.exerciseMinutes, entry.exerciseGoal), color: VivordoWidgetPalette.mint)
      }
      .padding(.top, 4)
      Spacer(minLength: 4)
      Text(entry.hasMetrics ? entry.updatedAt.map { "As of \(vivordoTime($0))" } ?? "Today" : "Open Vivordo to update")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(14)
    .accessibilityElement(children: .combine)
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
        .widgetAccentable()
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

  static func current(key: String = "calendarEvents") -> [VivordoCalendarEvent] {
    guard let rawEvents = VivordoWidgetData.defaults.array(forKey: key) as? [[String: Any]] else {
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
  // How long a tapped day stays selected before the widget returns to today.
  static let selectionLifetime: TimeInterval = 10 * 60

  let date: Date
  let weekDates: [Date]
  let selectedDate: Date
  let events: [VivordoCalendarEvent]
  let connected: Bool

  static func current(date: Date = .now) -> VivordoCalendarEntry {
    let weekDates = VivordoCalendarDates.currentWeek(now: date)
    let selectedAt = Date(timeIntervalSince1970: VivordoWidgetData.defaults.double(forKey: "calendarSelectedAt"))
    let selectionActive = date.timeIntervalSince(selectedAt) < selectionLifetime &&
      VivordoCalendarDates.calendar.isDate(selectedAt, inSameDayAs: date)
    let selectedKey = selectionActive ? VivordoWidgetData.defaults.string(forKey: "calendarSelectedDay") : nil
    let selectedDate = weekDates.first {
      VivordoCalendarDates.dayKey(for: $0) == selectedKey
    } ?? VivordoCalendarDates.calendar.startOfDay(for: date)
    return VivordoCalendarEntry(
      date: date,
      weekDates: weekDates,
      selectedDate: selectedDate,
      events: VivordoCalendarEvent.current(),
      connected: VivordoWidgetData.defaults.bool(forKey: "dashboardCalendarConnected")
    )
  }

  var selectedEvents: [VivordoCalendarEvent] {
    events.filter {
      VivordoCalendarDates.calendar.isDate($0.start, inSameDayAs: selectedDate) &&
        ($0.isAllDay || $0.end > date)
    }
  }

  /// Today's timed events that have not ended yet.
  var todayRemaining: [VivordoCalendarEvent] {
    events.filter {
      !$0.isAllDay && $0.end > date && VivordoCalendarDates.calendar.isDate($0.start, inSameDayAs: date)
    }
  }

  var availability: String {
    let upcoming = todayRemaining
    if let active = upcoming.first(where: { $0.start <= date }) {
      return "Busy until \(vivordoTime(active.end))"
    }
    if let next = upcoming.first { return "Free until \(vivordoTime(next.start))" }
    return "Free rest of today"
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
      ],
      connected: true
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (VivordoCalendarEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : .current())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<VivordoCalendarEntry>) -> Void) {
    let now = Date.now
    let calendar = VivordoCalendarDates.calendar
    let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let selectedAt = Date(timeIntervalSince1970: VivordoWidgetData.defaults.double(forKey: "calendarSelectedAt"))
    // Entries where the view changes: an event starts or ends, the tapped day
    // expires, and midnight.
    var dates = [now, midnight, selectedAt.addingTimeInterval(VivordoCalendarEntry.selectionLifetime)]
    dates += VivordoCalendarEvent.current().flatMap { [$0.start, $0.end] }
    let entries = Set(dates.filter { $0 >= now && $0 <= midnight }).sorted().map {
      VivordoCalendarEntry.current(date: $0)
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
  }
}

private func vivordoEventColor(_ kind: String) -> Color {
  switch kind {
  case "running": return .orange
  case "fitness": return VivordoWidgetPalette.coral
  case "sport": return VivordoWidgetPalette.mint
  default: return VivordoWidgetPalette.purple
  }
}

private struct CalendarWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: VivordoCalendarEntry

  private var calendar: Calendar { VivordoCalendarDates.calendar }
  private var isToday: Bool { calendar.isDate(entry.selectedDate, inSameDayAs: entry.date) }

  var body: some View {
    Group {
      if family == .accessoryRectangular {
        CalendarAccessoryView(entry: entry)
      } else {
        medium
      }
    }
    .widgetURL(URL(string: "com.vivordo.health://widget/calendar"))
  }

  private var header: String {
    let count = entry.selectedEvents.count
    if isToday { return entry.connected ? entry.availability : "Open Vivordo to sync" }
    return count == 0 ? "No events" : count == 1 ? "1 event" : "\(count) events"
  }

  private var medium: some View {
    let events = entry.selectedEvents
    return HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 0) {
        Text(entry.selectedDate, format: .dateTime.weekday(.wide))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(entry.selectedDate, format: .dateTime.day())
          .font(.system(size: 34, weight: .semibold, design: .rounded))
        Spacer(minLength: 4)
        weekStrip
      }
      .frame(width: 126)

      VStack(alignment: .leading, spacing: 6) {
        Text(header)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        ForEach(Array(events.prefix(2))) { event in
          eventRow(event)
        }
        Spacer(minLength: 0)
        if events.count > 2 {
          Text("+\(events.count - 2) more\(isToday ? " today" : "")")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var weekStrip: some View {
    HStack(spacing: 0) {
      ForEach(entry.weekDates, id: \.self) { day in
        let selected = calendar.isDate(day, inSameDayAs: entry.selectedDate)
        let hasEvents = entry.events.contains { calendar.isDate($0.start, inSameDayAs: day) }
        Button(intent: SelectVivordoCalendarDayIntent(dayKey: VivordoCalendarDates.dayKey(for: day))) {
          VStack(spacing: 2) {
            Text(day, format: .dateTime.weekday(.narrow))
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(.secondary)
            Text(day, format: .dateTime.day())
              .font(.system(size: 11, weight: selected ? .bold : .medium))
              .foregroundStyle(selected ? Color.white : Color.primary)
              .frame(width: 18, height: 18)
              .background {
                if selected {
                  Circle().fill(VivordoWidgetPalette.purple).widgetAccentable()
                }
              }
            Circle()
              .fill(hasEvents ? VivordoWidgetPalette.purple : .clear)
              .frame(width: 4, height: 4)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func eventRow(_ event: VivordoCalendarEvent) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(vivordoEventColor(event.kind))
        .frame(width: 3)
        .widgetAccentable()
      VStack(alignment: .leading, spacing: 1) {
        Text(event.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Text(event.isAllDay ? "All day" : "\(vivordoTime(event.start)) – \(vivordoTime(event.end))")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(height: 34)
  }
}

private struct CalendarAccessoryView: View {
  let entry: VivordoCalendarEntry

  var body: some View {
    let upcoming = entry.todayRemaining
    let active = upcoming.first { $0.start <= entry.date }
    let later = upcoming.filter { $0.start > entry.date }
    VStack(alignment: .leading, spacing: 1) {
      Label(entry.connected ? entry.availability : "Open Vivordo to sync", systemImage: "calendar")
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .widgetAccentable()
      if let active {
        Text("Now: \(active.title)")
          .lineLimit(1)
          .privacySensitive()
      }
      if let next = later.first {
        // When free, the header already has the start time, so show length.
        Text("Next: \(next.title) · \(active == nil ? vivordoDuration(next.end.timeIntervalSince(next.start)) : vivordoTime(next.start))")
          .lineLimit(1)
          .privacySensitive()
      }
      if active == nil, later.count > 1 {
        Text("Then \(vivordoTime(later[1].start)) \(later[1].title)")
          .lineLimit(1)
          .foregroundStyle(.secondary)
          .privacySensitive()
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
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
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
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
    .configurationDisplayName("Today’s Activity")
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
    .description("See when you’re free next and switch days without opening Vivordo.")
    .supportedFamilies([.systemMedium, .accessoryRectangular])
    .contentMarginsDisabled()
  }
}

// A separate iOS 27 family leaves the existing small and medium widgets intact.
@available(iOS 27.0, *)
private struct DayDashboardWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "VivordoDayDashboard", provider: DayDashboardProvider()) { entry in
      DayDashboardView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
        .widgetURL(URL(string: "com.vivordo.health://widget/myday"))
        .privacySensitive()
    }
    .configurationDisplayName("My Day Overview")
    .description("Your stress, schedule, activity and priorities, with quick access to mood and workouts.")
    .supportedFamilies([.systemExtraLargePortrait])
    .contentMarginsDisabled()
  }
}

private struct DashboardPriority: Identifiable {
  let id: Int
  let title: String
  let time: String
  let completed: Bool
  let start: Date?
  let source: String
  let isAllDay: Bool
}

private struct DayDashboardEntry: TimelineEntry {
  let date: Date
  let metrics: VivordoWidgetEntry
  let name: String
  let calendarConnected: Bool
  let events: [VivordoCalendarEvent]
  let priorities: [DashboardPriority]

  static func current(date: Date = .now) -> Self {
    let defaults = VivordoWidgetData.defaults
    let day = VivordoCalendarDates.dayKey(for: date)
    let calendarUpdated = Date(timeIntervalSince1970: defaults.double(forKey: "calendarWeekUpdatedAt") / 1000)
    let raw = defaults.string(forKey: "dashboardPrioritiesDay") == day
      ? (defaults.array(forKey: "dashboardPriorities") as? [[String: Any]] ?? []) : []
    return Self(date: date, metrics: .current(date: date),
                name: defaults.string(forKey: "dashboardName") ?? "",
                calendarConnected: defaults.bool(forKey: "dashboardCalendarConnected") &&
                  Calendar.current.isDate(calendarUpdated, inSameDayAs: date),
                events: VivordoCalendarEvent.current(key: "dashboardEvents"),
                priorities: raw.enumerated().map { index, value in
                  DashboardPriority(id: index, title: value["title"] as? String ?? "Priority",
                                    time: value["time"] as? String ?? "Anytime",
                                    completed: value["completed"] as? Bool ?? false,
                                    start: (value["startAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
                                    source: value["source"] as? String ?? "manual",
                                    isAllDay: value["isAllDay"] as? Bool ?? false)
                })
  }

  var timedEvents: [VivordoCalendarEvent] {
    let start = Calendar.current.startOfDay(for: date)
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    return events.filter { !$0.isAllDay && $0.start < end && $0.end > start }
  }

  /// Today's timed events that have not ended yet.
  var remainingToday: [VivordoCalendarEvent] {
    calendarConnected ? timedEvents.filter { $0.end > date } : []
  }

  var activeEvent: VivordoCalendarEvent? { remainingToday.first { $0.start <= date } }
  var nextToday: VivordoCalendarEvent? { remainingToday.first { $0.start > date } }
  var eventsDoneToday: Int { calendarConnected ? timedEvents.filter { $0.end <= date }.count : 0 }
  var prioritiesDone: Int { priorities.filter(\.completed).count }

  /// Tomorrow's events, or nil without a calendar. The app always publishes
  /// through tomorrow (on Sunday it adds next Monday).
  var tomorrowEvents: [VivordoCalendarEvent]? {
    guard calendarConnected else { return nil }
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    return events.filter { calendar.isDate($0.start, inSameDayAs: tomorrow) }
  }

  var freeText: String {
    Calendar.current.component(.hour, from: date) >= 17 ? "Your evening is clear." : "The rest of your day is clear."
  }

  var summary: String {
    guard calendarConnected else { return "Your day, at a glance." }
    if let active = activeEvent { return "In \(active.title) until \(vivordoTime(active.end))." }
    if let next = nextToday { return "Free until \(vivordoTime(next.start)), then \(next.title)." }
    if let first = tomorrowEvents?.first(where: { !$0.isAllDay }) {
      return "\(freeText) \(first.title) at \(vivordoTime(first.start)) tomorrow."
    }
    return freeText
  }
}

private struct DayDashboardProvider: TimelineProvider {
  func placeholder(in context: Context) -> DayDashboardEntry { .current() }
  func getSnapshot(in context: Context, completion: @escaping (DayDashboardEntry) -> Void) {
    completion(.current())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<DayDashboardEntry>) -> Void) {
    let now = Date.now
    // Time-driven entries let Now & Next advance even when Flutter is asleep.
    let events = VivordoCalendarEvent.current(key: "dashboardEvents")
    let horizon = now.addingTimeInterval(3600)
    var dates = [now, Calendar.current.date(byAdding: .day, value: 1,
                        to: Calendar.current.startOfDay(for: now))!]
    dates += (1...4).map { now.addingTimeInterval(Double($0) * 900) }
    dates += events.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < horizon }
    completion(Timeline(entries: Array(Set(dates)).sorted().map { .current(date: $0) },
                        policy: .after(horizon)))
  }
}

private func vivordoPill(_ state: (label: String, color: Color)) -> some View {
  Text(state.label)
    .font(.caption.weight(.semibold))
    .lineLimit(1)
    .padding(.horizontal, 10)
    .padding(.vertical, 3)
    .background(state.color.opacity(0.22), in: Capsule())
}

private struct DayDashboardView: View {
  let entry: DayDashboardEntry
  private var metrics: VivordoWidgetEntry { entry.metrics }
  private let accent = VivordoWidgetPalette.accent

  private var greeting: String {
    // Same cut-offs as the Home greeting in the app.
    let hour = Calendar.current.component(.hour, from: entry.date)
    let time = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
    return entry.name.isEmpty ? time : "\(time), \(entry.name)"
  }

  private func destination(_ name: String) -> URL {
    URL(string: "com.vivordo.health://widget/\(name)")!
  }

  private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
      // Link tints its label; an explicit colour keeps tile text neutral.
      .foregroundStyle(Color.primary)
  }

  private func heading(_ title: String) -> some View {
    Text(title).font(.caption).foregroundStyle(.secondary)
  }

  var body: some View {
    GeometryReader { geometry in
      // Fit the whole composition on the smaller supported iPhones without
      // clipping the actions below the fold. No scrolling inside WidgetKit.
      let scale = min(geometry.size.width / 360, geometry.size.height / 740)
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 6) {
          VivordoMark()
            .fill(accent)
            .frame(width: 25, height: 20)
            .widgetAccentable()
            .accessibilityHidden(true)
          Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 3) {
          Text(greeting)
            .font(.system(size: 24, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
          Text(entry.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        HStack(spacing: 10) {
          Link(destination: destination("home")) { tile { stressTile.frame(maxHeight: .infinity, alignment: .top) } }
          Link(destination: destination("myday")) { tile { prioritiesTile.frame(maxHeight: .infinity, alignment: .top) } }
        }
        .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 6) {
          heading("Now and next")
          Link(destination: destination("calendar")) { tile { nowAndNext } }
        }
        VStack(alignment: .leading, spacing: 6) {
          heading("Activity")
          Link(destination: destination("fitness")) { tile { activity } }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            heading("Priorities")
            Spacer()
            Link("Open My Day ›", destination: destination("myday"))
              .font(.caption)
              .foregroundStyle(accent)
          }
          Link(destination: destination("myday")) { tile { priorityList } }
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        HStack(spacing: 10) {
          shortcut("Mood check-in", icon: "heart.fill", color: .pink, route: "mood")
          shortcut("Start workout", icon: "dumbbell.fill", color: accent, route: "workout")
        }
      }
      .padding(18)
      .frame(width: 360, height: 740, alignment: .top)
      .scaleEffect(scale)
      .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }
  }

  private var stressTile: some View {
    VStack(alignment: .leading, spacing: 6) {
      heading("Stress")
      HStack(spacing: 10) {
        Text(metrics.hasStress ? "\(metrics.stress)" : "—")
          .font(.system(size: 34, weight: .semibold, design: .rounded))
          .foregroundStyle(metrics.hasStress ? .primary : .tertiary)
        if let state = metrics.stressState {
          FitnessArc(progress: Double(metrics.stress) / 100, color: state.color, lineWidth: 5)
            .frame(width: 32, height: 32)
        }
      }
      if let state = metrics.stressState {
        vivordoPill(state)
      } else {
        Text("No reading today").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private var prioritiesTile: some View {
    let total = entry.priorities.count
    let done = entry.prioritiesDone
    return VStack(alignment: .leading, spacing: 6) {
      heading("Priorities")
      HStack(spacing: 10) {
        if total > 0 {
          (Text("\(done)").font(.system(size: 34, weight: .semibold, design: .rounded))
            + Text("/\(total)").font(.system(size: 18, weight: .semibold, design: .rounded))
              .foregroundStyle(.secondary))
          FitnessArc(progress: Double(done) / Double(total), color: accent, lineWidth: 5)
            .frame(width: 32, height: 32)
        } else {
          Text("—")
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
        }
      }
      Text(total == 0 ? "None set today" : done == total ? "All done" : "\(total - done) left today")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var nowAndNext: some View {
    let active = entry.activeEvent
    let upcoming: (event: VivordoCalendarEvent, when: String)? = entry.nextToday.map { ($0, vivordoTime($0.start)) }
      ?? entry.tomorrowEvents?.first.map { ($0, $0.isAllDay ? "Tomorrow" : "Tomorrow \(vivordoTime($0.start))") }
    return VStack(alignment: .leading, spacing: 8) {
      if !entry.calendarConnected {
        Text("Open Vivordo for your schedule").font(.subheadline.weight(.semibold))
      } else {
        HStack(spacing: 8) {
          Circle()
            .fill(active == nil ? VivordoWidgetPalette.mint : accent)
            .frame(width: 8, height: 8)
          Text(active.map { "\($0.title) until \(vivordoTime($0.end))" }
            ?? entry.nextToday.map { "Free until \(vivordoTime($0.start))" }
            ?? "Free rest of today")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        }
        if let upcoming {
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
              .fill(vivordoEventColor(upcoming.event.kind))
              .frame(width: 3, height: 16)
              .padding(.horizontal, 2.5)
              .widgetAccentable()
            Text(upcoming.event.title).font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            Text(upcoming.when).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      }
    }
  }

  private var activity: some View {
    VStack(spacing: 10) {
      activityRow(value: metrics.steps, goal: metrics.stepsGoal, unit: "steps", color: accent)
      activityRow(value: metrics.calories, goal: metrics.caloriesGoal, unit: "cal", color: VivordoWidgetPalette.coral)
      activityRow(value: metrics.exerciseMinutes, goal: metrics.exerciseGoal, unit: "min", color: VivordoWidgetPalette.mint)
    }
  }

  private func activityRow(value: Int, goal: Int, unit: String, color: Color) -> some View {
    VStack(spacing: 4) {
      HStack {
        (Text(metrics.hasMetrics ? value.formatted() : "—").font(.subheadline.weight(.semibold))
          + Text(" \(unit)").font(.caption).foregroundStyle(.secondary))
        Spacer()
        if metrics.hasMetrics && value >= goal {
          Label("Goal met", systemImage: "checkmark")
            .font(.caption)
            .foregroundStyle(.green)
        } else {
          Text("of \(goal.formatted())").font(.caption).foregroundStyle(.secondary)
        }
      }
      ProgressBar(progress: metrics.hasMetrics ? Double(value) / Double(goal) : 0, color: color)
    }
  }

  private var priorityList: some View {
    let ordered = entry.priorities.filter { !$0.completed } + entry.priorities.filter(\.completed)
    return VStack(alignment: .leading, spacing: 9) {
      if ordered.isEmpty {
        Text("No priorities yet").font(.subheadline.weight(.semibold))
        Text("Add one in My Day.").font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(Array(ordered.prefix(3))) { priority in
          HStack(spacing: 9) {
            Image(systemName: priority.completed ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(accent)
              .widgetAccentable()
            Text(priority.title)
              .font(.subheadline)
              .strikethrough(priority.completed)
              .foregroundStyle(priority.completed ? .secondary : .primary)
              .lineLimit(1)
            Spacer(minLength: 4)
            if !priority.completed {
              Text(priority.time).font(.caption2).foregroundStyle(.secondary)
            }
          }
        }
        if ordered.count > 3 {
          Text("+\(ordered.count - 3) more").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func shortcut(_ title: String, icon: String, color: Color, route: String) -> some View {
    Link(destination: destination(route)) {
      HStack(spacing: 8) {
        Image(systemName: icon).foregroundStyle(color).widgetAccentable()
        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15)))
      .foregroundStyle(Color.primary)
    }
  }
}

private struct TodayAgendaWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "VivordoTodayAgenda", provider: DayDashboardProvider()) { entry in
      TodayAgendaView(entry: entry)
        .containerBackground(for: .widget) { VivordoWidgetBackground() }
        .widgetURL(URL(string: "com.vivordo.health://widget/myday"))
        .privacySensitive()
    }
    .configurationDisplayName("Today: Events & Priorities")
    .description("Your remaining calendar events and unfinished priorities in one timeline.")
    .supportedFamilies([.systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

private struct TodayAgendaItem: Identifiable {
  let id: String
  let title: String
  let time: String
  let badge: String
  let start: Date?
  let isPriority: Bool
  let isActive: Bool
  let color: Color
}

private extension DayDashboardEntry {
  func agendaItem(for event: VivordoCalendarEvent, index: Int) -> TodayAgendaItem {
    let active = !event.isAllDay && event.start <= date && event.end > date
    return TodayAgendaItem(
      id: "event-\(index)-\(event.id)", title: event.title,
      time: event.isAllDay ? "All day" : vivordoTime(event.start),
      badge: event.isAllDay ? "Event"
        : active ? "until \(vivordoTime(event.end))"
        : vivordoDuration(event.end.timeIntervalSince(event.start)),
      start: event.isAllDay ? Calendar.current.startOfDay(for: event.start) : event.start,
      isPriority: false, isActive: active, color: vivordoEventColor(event.kind))
  }

  var agendaItems: [TodayAgendaItem] {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: date)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
    let todayEvents = calendarConnected ? events.filter {
      $0.start < dayEnd && $0.end > date
    } : []
    var items = todayEvents.enumerated().map { agendaItem(for: $1, index: $0) }
    for priority in priorities where !priority.completed {
      // Generated priorities mirror their source event. Keep the calendar row
      // rather than showing the same commitment twice.
      let mirrorsEvent = priority.source == "calendar" && todayEvents.contains {
        $0.title == priority.title && $0.start == priority.start
      }
      if mirrorsEvent { continue }
      items.append(TodayAgendaItem(id: "priority-\(priority.id)", title: priority.title,
                                   time: priority.time, badge: "Priority",
                                   start: priority.isAllDay ? nil : priority.start, isPriority: true,
                                   isActive: false, color: .secondary))
    }
    return items.sorted {
      let lhs = $0.start ?? .distantFuture
      let rhs = $1.start ?? .distantFuture
      if lhs != rhs { return lhs < rhs }
      if $0.isPriority != $1.isPriority { return !$0.isPriority }
      return $0.id < $1.id
    }
  }
}

private struct TodayAgendaView: View {
  @Environment(\.widgetFamily) private var family
  let entry: DayDashboardEntry

  var body: some View {
    TodayAgendaContent(entry: entry, large: family == .systemLarge)
  }
}

private struct TodayAgendaContent: View {
  let entry: DayDashboardEntry
  let large: Bool
  private let accent = VivordoWidgetPalette.accent

  private func destination(_ name: String) -> URL {
    URL(string: "com.vivordo.health://widget/\(name)")!
  }

  var body: some View {
    let items = entry.agendaItems
    let shown = Array(items.prefix(large ? 7 : 3))
    VStack(alignment: .leading, spacing: 0) {
      Link(destination: destination("myday")) {
        HStack(spacing: 6) {
          VivordoMark()
            .fill(accent)
            .frame(width: 20, height: 16)
            .widgetAccentable()
            .accessibilityHidden(true)
          Text("Today").font(.system(size: 16, weight: .semibold))
          Spacer(minLength: 4)
          Text("\(entry.date.formatted(.dateTime.weekday(.abbreviated).day()))\(items.isEmpty ? "" : " · \(items.count) left")")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
      }
      if shown.isEmpty {
        caughtUp.padding(.top, 12)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
            Link(destination: destination(item.isPriority ? "myday" : "calendar")) { row(item).foregroundStyle(Color.primary) }
            if index < shown.count - 1, !item.isActive, !shown[index + 1].isActive {
              Divider()
            }
          }
        }
        .padding(.top, 6)
        Spacer(minLength: 0)
        if items.count > shown.count {
          Text("+\(items.count - shown.count) more today").font(.caption2).foregroundStyle(.secondary)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func row(_ item: TodayAgendaItem) -> some View {
    HStack(spacing: 8) {
      Text(item.isActive ? "Now" : item.time)
        .font(.caption2.weight(item.isActive ? .semibold : .regular))
        .foregroundStyle(item.isActive ? AnyShapeStyle(accent) : AnyShapeStyle(.secondary))
        .frame(width: 52, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      RoundedRectangle(cornerRadius: 1.5)
        .fill(item.color)
        .frame(width: 3, height: 24)
        .widgetAccentable()
      Text(item.title)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 3) {
        if item.isPriority { Image(systemName: "circle").font(.system(size: 8, weight: .semibold)) }
        Text(item.badge)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .overlay(Capsule().stroke(VivordoWidgetPalette.track))
    }
    .frame(height: 34)
    .padding(.horizontal, item.isActive ? 6 : 0)
    .background {
      if item.isActive { RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.12)) }
    }
    .padding(.horizontal, item.isActive ? -6 : 0)
  }

  private var doneSummary: String {
    var parts: [String] = []
    if entry.eventsDoneToday > 0 {
      parts.append("\(entry.eventsDoneToday) \(entry.eventsDoneToday == 1 ? "event" : "events") done")
    }
    if !entry.priorities.isEmpty {
      parts.append("\(entry.prioritiesDone) of \(entry.priorities.count) priorities")
    }
    return parts.isEmpty ? "Nothing left on today’s list" : parts.joined(separator: " · ")
  }

  @ViewBuilder private var caughtUp: some View {
    if !entry.calendarConnected && entry.priorities.isEmpty {
      Text("Your day at a glance").font(.subheadline.bold())
      Text("Open Vivordo to refresh your day.").font(.caption).foregroundStyle(.secondary)
      Spacer(minLength: 0)
    } else {
      HStack(spacing: 10) {
        Image(systemName: "checkmark")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 32, height: 32)
          .background(VivordoWidgetPalette.mint, in: Circle())
          .widgetAccentable()
        VStack(alignment: .leading, spacing: 1) {
          Text("All caught up").font(.system(size: 15, weight: .semibold))
          Text(large ? entry.freeText : doneSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      if large { largeCaughtUp } else { mediumTomorrow }
    }
  }

  @ViewBuilder private var mediumTomorrow: some View {
    Spacer(minLength: 0)
    if let first = entry.tomorrowEvents?.first {
      Divider().padding(.bottom, 6)
      HStack(spacing: 8) {
        Text("Tomorrow").font(.caption2).foregroundStyle(.secondary)
        RoundedRectangle(cornerRadius: 1.5).fill(vivordoEventColor(first.kind)).frame(width: 3, height: 16)
          .widgetAccentable()
        Text(first.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        Spacer(minLength: 4)
        Text(first.isAllDay ? "All day" : vivordoTime(first.start)).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder private var largeCaughtUp: some View {
    HStack(spacing: 16) {
      stat("\(entry.eventsDoneToday)", entry.eventsDoneToday == 1 ? "event" : "events")
      if !entry.priorities.isEmpty {
        stat("\(entry.prioritiesDone)/\(entry.priorities.count)", "priorities")
      }
      if entry.metrics.hasMetrics {
        stat("\(entry.metrics.exerciseMinutes)", "active min")
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .topLeading) {
      Text("Done today").font(.caption2).foregroundStyle(.secondary).padding([.leading, .top], 10)
    }
    .padding(.top, 14)
    if let tomorrow = entry.tomorrowEvents {
      let calendar = Calendar.current
      let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: entry.date)!
      Text("Tomorrow · \(tomorrowDate.formatted(.dateTime.weekday(.abbreviated).day()))")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 14)
      if tomorrow.isEmpty {
        Text("Nothing scheduled").font(.subheadline).padding(.top, 6)
      }
      VStack(spacing: 0) {
        ForEach(Array(tomorrow.prefix(3).enumerated()), id: \.element.id) { index, event in
          row(entry.agendaItem(for: event, index: index))
          if index < min(tomorrow.count, 3) - 1 { Divider() }
        }
      }
      Spacer(minLength: 0)
      if tomorrow.count > 3 {
        Text("+\(tomorrow.count - 3) more tomorrow").font(.caption2).foregroundStyle(.secondary)
      }
    } else {
      Spacer(minLength: 0)
    }
  }

  private func stat(_ value: String, _ label: String) -> some View {
    (Text(value).font(.subheadline.weight(.semibold)) + Text(" \(label)").font(.caption).foregroundStyle(.secondary))
      .padding(.top, 16)
  }
}
