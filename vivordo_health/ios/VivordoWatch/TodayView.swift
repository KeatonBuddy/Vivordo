import SwiftUI

/// Today: Stress with the latest heart rate, Capacity and Demand, what's next,
/// as the phone last showed them.
struct TodayView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @EnvironmentObject private var resets: ResetScheduler
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ScrollView {
      if let snapshot = store.snapshot {
        content(snapshot)
      } else {
        empty
      }
    }
    .navigationTitle("Today")
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { store.refresh() }
    }
  }

  private var empty: some View {
    VStack(spacing: 8) {
      Text("Nothing here yet")
        .font(.headline)
      Text("Open Vivordo on your iPhone once and today's scores will follow you here.")
        .font(.footnote)
        .foregroundStyle(WatchPalette.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 24)
  }

  private func content(_ s: WatchSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      NavigationLink {
        StressView()
      } label: {
        HStack(spacing: 10) {
          ScoreRing(value: s.stressScore, color: WatchPalette.stress)
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 2) {
            Text("Stress").font(.headline)
            Text(s.latestHeartRate.map { "\($0) bpm" } ?? "No reading yet")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(WatchPalette.stress)
          }
          Spacer(minLength: 0)
        }
      }
      .buttonStyle(.plain)

      HStack(spacing: 6) {
        tile("Capacity", value: s.capacityScore, color: WatchPalette.capacity,
             note: s.capacityScore == nil ? "Not yet today" : s.capacityLabel.capitalized)
        tile("Demand", value: s.demand, color: WatchPalette.demand,
             note: s.demandHeadline)
      }
      .fixedSize(horizontal: false, vertical: true)

      let done = s.priorities.filter(\.completed).count
      row("My Day", icon: "checklist", color: WatchPalette.capacity,
          detail: s.priorities.isEmpty ? "No priorities today" : "\(done) of \(s.priorities.count) done") {
        MyDayView()
      }
      row("Energy", icon: "bolt.fill", color: WatchPalette.demand, detail: "Quick check-in") {
        CheckInView()
      }
      row("Fitness", icon: "figure.walk", color: WatchPalette.stress,
          detail: s.steps.map { "\($0) steps" } ?? "No steps yet") {
        FitnessView()
      }

      if let event = s.nextEvent {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Next · \(event.start, format: .dateTime.hour().minute())")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(WatchPalette.secondary)
            Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(1)
          }
          Spacer()
        }
        .padding(10)
        .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
      }

      Button {
        resets.resetRequested = true
      } label: {
        Label("Take a minute", systemImage: "wind")
          .font(.footnote.weight(.semibold))
          .frame(maxWidth: .infinity)
      }
      .tint(WatchPalette.capacity)

      if let at = s.updatedAt {
        Text("From your iPhone, \(at, format: .relative(presentation: .named))")
          .font(.caption2)
          .foregroundStyle(WatchPalette.secondary)
          .padding(.top, 2)
      }
    }
    .scenePadding(.horizontal)
  }

  private func row<Destination: View>(
    _ title: String, icon: String, color: Color, detail: String,
    @ViewBuilder destination: () -> Destination
  ) -> some View {
    NavigationLink(destination: destination) {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.footnote.weight(.semibold)).foregroundStyle(color)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.footnote.weight(.semibold))
          Text(detail).font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    }
  }

  private func tile(_ title: String, value: Int?, color: Color, note: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
      Text(value.map(String.init) ?? "–")
        .font(.system(.title3, design: .rounded).weight(.bold))
        .foregroundStyle(color)
      Text(note.isEmpty ? " " : note)
        .font(.caption2)
        .foregroundStyle(WatchPalette.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(8)
    .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
  }
}
