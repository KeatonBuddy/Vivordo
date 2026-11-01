import SwiftUI
import WidgetKit

@main
struct VivordoWatchComplicationsBundle: WidgetBundle {
  var body: some Widget {
    CapacityComplication()
  }
}

struct CapacityEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchSnapshot?
}

struct CapacityProvider: TimelineProvider {
  func placeholder(in context: Context) -> CapacityEntry {
    CapacityEntry(date: .now, snapshot: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (CapacityEntry) -> Void) {
    completion(CapacityEntry(date: .now, snapshot: WatchSnapshot.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CapacityEntry>) -> Void) {
    // The watch app reloads these the moment the phone sends a new snapshot;
    // this is the fallback for a day change with nothing new from the phone.
    let now = Date.now
    let snapshot = WatchSnapshot.load(now: now)
    // Live Capacity steps down as today's plan happens, so the face moves
    // between the phone's updates.
    let steps = (snapshot?.capacityLeftSteps ?? []).prefix(24).map {
      CapacityEntry(date: $0, snapshot: WatchSnapshot.load(now: $0))
    }
    // Midnight drops yesterday's live Capacity even if no reload runs.
    let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
    completion(Timeline(entries: [CapacityEntry(date: now, snapshot: snapshot)] + steps
                          + [CapacityEntry(date: midnight, snapshot: WatchSnapshot.load(now: midnight))],
                        policy: .after(now.addingTimeInterval(30 * 60))))
  }
}

struct CapacityComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "VivordoCapacity", provider: CapacityProvider()) { entry in
      CapacityComplicationView(entry: entry)
        .containerBackground(for: .widget) { Color.clear }
    }
    .configurationDisplayName("Capacity")
    .description("Today's Capacity, with Demand and Stress.")
    .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
  }
}

struct CapacityComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CapacityEntry

  /// Live during the day: what's left of this morning's Capacity.
  private var left: Int? { entry.snapshot?.capacityLeft }
  private var capacity: Int? { left ?? entry.snapshot?.capacityScore }
  private var capacityRange: Double { Double(max(entry.snapshot?.capacityMorning ?? 100, 1)) }
  private var tonight: String? {
    entry.snapshot?.capacityByTonight.map { $0 < 0 ? "Short by \(-$0)" : "\($0) by tonight" }
  }
  private var demand: Int? { entry.snapshot?.demand }
  private var stress: Int? { entry.snapshot?.stressScore }

  var body: some View {
    switch family {
    case .accessoryCircular:
      Gauge(value: Double(capacity ?? 0), in: 0...(left == nil ? 100 : capacityRange)) {
        Text(left == nil ? "Capacity" : "left")
      } currentValueLabel: {
        Text(capacity.map(String.init) ?? "–")
          .font(.system(.title3, design: .rounded).weight(.bold))
      }
      .gaugeStyle(.accessoryCircularCapacity)
      .tint(WatchPalette.capacity)
      .widgetAccentable()
    case .accessoryCorner:
      Text(capacity.map(String.init) ?? "–")
        .font(.system(.title2, design: .rounded).weight(.bold))
        .widgetCurvesContent()
        .widgetLabel {
          Gauge(value: Double(demand ?? 0), in: 0...100) {
            Text("Demand")
          }
          .tint(WatchPalette.demand)
        }
    case .accessoryRectangular:
      HStack(spacing: 8) {
        ScoreRing(value: capacity, color: WatchPalette.capacity, lineWidth: 6)
          .frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 1) {
          Text(capacityLabel)
            .font(.headline)
            .foregroundStyle(WatchPalette.capacity)
            .widgetAccentable()
          Text(left == nil ? "Demand \(demand.map(String.init) ?? "–")" : tonight ?? "")
            .font(.caption)
          Text("Stress \(stress.map(String.init) ?? "–")")
            .font(.caption)
        }
        Spacer(minLength: 0)
      }
    default:
      if let left, let tonight {
        // The inline slot is narrow: drop words until it fits.
        ViewThatFits {
          Text("Capacity \(left) left · \(tonight)")
          Text("\(left) left · \(tonight)")
          Text("Capacity \(left) left")
        }
      } else {
        Text("Capacity \(capacity.map(String.init) ?? "–") · Demand \(demand.map(String.init) ?? "–")")
      }
    }
  }

  private var capacityLabel: String {
    if let left { return "\(left) left" }
    guard let label = entry.snapshot?.capacityLabel, !label.isEmpty, capacity != nil else {
      return "Capacity"
    }
    return label.capitalized
  }
}
