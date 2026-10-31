import SwiftUI

/// The one Phase 1 screen: Capacity, Demand, Stress and what's next, as the
/// phone last showed them.
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
      HStack(spacing: 12) {
        ScoreRing(value: s.capacityScore, color: WatchPalette.capacity)
          .frame(width: 76, height: 76)
        VStack(alignment: .leading, spacing: 2) {
          Text("Capacity").font(.headline)
          Text(s.capacityScore == nil ? "Not yet today" : s.capacityLabel.capitalized)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WatchPalette.capacity)
          if !s.capacityNote.isEmpty {
            Text(s.capacityNote)
              .font(.caption2)
              .foregroundStyle(WatchPalette.secondary)
              .lineLimit(2)
          }
        }
      }

      HStack(spacing: 6) {
        tile("Demand", value: s.demand, color: WatchPalette.demand,
             note: s.demandHeadline)
        tile("Stress", value: s.stressScore, color: WatchPalette.stress,
             note: s.latestHeartRate.map { "\($0) bpm" } ?? "")
      }
      .fixedSize(horizontal: false, vertical: true)

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
  }

  private func tile(_ title: String, value: Int?, color: Color, note: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
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
    .padding(10)
    .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
  }
}
