import SwiftUI

/// The Stress score, what is driving it, and a heart rate read on the wrist
/// while the screen is open.
struct StressView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @EnvironmentObject private var resets: ResetScheduler
  @StateObject private var heart = HeartRateReader()

  var body: some View {
    let s = store.snapshot
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          ScoreRing(value: s?.stressScore, color: WatchPalette.stress, lineWidth: 8)
            .frame(width: 56, height: 56)
          VStack(alignment: .leading, spacing: 1) {
            Text("Now").font(.caption2).foregroundStyle(WatchPalette.secondary)
            Text(heart.bpm.map { "\($0) bpm" } ?? "Reading…")
              .font(.title3.weight(.bold))
              .foregroundStyle(WatchPalette.stress)
              .lineLimit(1).minimumScaleFactor(0.6)
          }
        }
        if let average = s?.averageHeartRate {
          Text("Today's average \(average) bpm")
            .font(.caption2).foregroundStyle(WatchPalette.secondary)
        }

        let drivers = s?.stressDrivers ?? []
        if drivers.isEmpty {
          Text(s?.stressScore == nil ? "No stress score yet today." : "Nothing is pushing it up.")
            .font(.footnote).foregroundStyle(WatchPalette.secondary)
        } else {
          Text("What's driving it")
            .font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
          ForEach(drivers, id: \.self) { driver in
            HStack(alignment: .top, spacing: 6) {
              Circle().fill(WatchPalette.stress).frame(width: 5, height: 5).padding(.top, 6)
              Text(driver).font(.footnote)
            }
          }
        }

        Button {
          resets.resetRequested = true
        } label: {
          Label("Take a minute", systemImage: "wind")
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .tint(WatchPalette.capacity)
      }
      .scenePadding(.horizontal)
    }
    .navigationTitle("Stress")
    .onAppear { heart.start() }
    .onDisappear { heart.stop() }
  }
}
