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
    let entry = CapacityEntry(date: .now, snapshot: WatchSnapshot.load())
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
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

  private var capacity: Int? { entry.snapshot?.capacityScore }
  private var demand: Int? { entry.snapshot?.demand }
  private var stress: Int? { entry.snapshot?.stressScore }

  var body: some View {
    switch family {
    case .accessoryCircular:
      Gauge(value: Double(capacity ?? 0), in: 0...100) {
        Text("Capacity")
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
          Text("Demand \(demand.map(String.init) ?? "–")")
            .font(.caption)
          Text("Stress \(stress.map(String.init) ?? "–")")
            .font(.caption)
        }
        Spacer(minLength: 0)
      }
    default:
      Text("Capacity \(capacity.map(String.init) ?? "–") · Demand \(demand.map(String.init) ?? "–")")
    }
  }

  private var capacityLabel: String {
    guard let label = entry.snapshot?.capacityLabel, !label.isEmpty, capacity != nil else {
      return "Capacity"
    }
    return label.capitalized
  }
}
