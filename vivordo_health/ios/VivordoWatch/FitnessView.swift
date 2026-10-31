import SwiftUI
import WatchKit

/// Today's movement against its goals, this week's training load, and a
/// heart rate check.
struct FitnessView: View {
  @EnvironmentObject private var store: WatchSnapshotStore

  var body: some View {
    let s = store.snapshot
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        goal("Steps", value: s?.steps, goal: s?.stepsGoal, color: WatchPalette.demand)
        goal("Active kcal", value: s?.activeCalories, goal: s?.activeCaloriesGoal,
             color: WatchPalette.stress)
        if let state = s?.trainingState, let words = Self.training[state] {
          VStack(alignment: .leading, spacing: 2) {
            Text("Training").font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
            Text(words).font(.footnote)
          }
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
        }
        NavigationLink {
          HeartCheckView()
        } label: {
          Label("Check heart rate", systemImage: "heart.fill")
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .tint(WatchPalette.stress)
      }
      .scenePadding(.horizontal)
    }
    .navigationTitle("Fitness")
  }

  private static let training = [
    "lighter": "A lighter week than your usual.",
    "steady": "A steady week, like your usual.",
    "building": "Building: more than your usual week.",
    "high": "A high week. Keep an eye on recovery.",
    "strained": "Strained: more than your body is used to.",
  ]

  private func goal(_ title: String, value: Int?, goal: Int?, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
        Spacer()
        Text(value.map { v in goal.map { "\(v) / \($0)" } ?? "\(v)" } ?? "–")
          .font(.caption2.weight(.semibold)).foregroundStyle(color)
          .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
      }
      ProgressView(value: Double(value ?? 0), total: Double(max(goal ?? 1, value ?? 0, 1)))
        .tint(color)
    }
    .padding(8)
    .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
  }
}

/// Thirty seconds on the sensor, then the average against today's.
struct HeartCheckView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @Environment(\.dismiss) private var dismiss
  @StateObject private var heart = HeartRateReader()
  @State private var secondsLeft = HeartCheckView.total
  @State private var readings: [Int] = []
  @State private var finished = false

  private static let total = 30
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 6) {
      if finished {
        result
      } else {
        Image(systemName: "heart.fill").font(.title2).foregroundStyle(WatchPalette.stress)
        Text(heart.bpm.map(String.init) ?? "–")
          .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
        Text("Hold still · \(secondsLeft)s").font(.footnote).foregroundStyle(WatchPalette.secondary)
      }
    }
    .navigationTitle("Heart rate")
    .onAppear { heart.start() }
    .onDisappear { heart.stop() }
    .onReceive(tick) { _ in step() }
  }

  private var average: Int? {
    readings.isEmpty ? nil : readings.reduce(0, +) / readings.count
  }

  private var result: some View {
    ScrollView {
      VStack(spacing: 6) {
        Text(average.map { "\($0) bpm" } ?? "No reading")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(WatchPalette.stress)
        Text(comparison).font(.footnote).foregroundStyle(WatchPalette.secondary)
          .multilineTextAlignment(.center)
        Button("Done") { dismiss() }.padding(.top, 4)
      }
      .scenePadding(.horizontal)
    }
  }

  private var comparison: String {
    guard let average else { return "The sensor didn't get a reading. Snug the band and try again." }
    guard let usual = store.snapshot?.averageHeartRate else { return "Today's first reading." }
    let delta = average - usual
    if abs(delta) <= 5 { return "About today's average of \(usual)." }
    return "\(abs(delta)) \(delta > 0 ? "above" : "below") today's average of \(usual)."
  }

  private func step() {
    guard !finished, heart.ready else { return }
    secondsLeft -= 1
    if let bpm = heart.bpm { readings.append(bpm) }
    if secondsLeft <= 0 {
      finished = true
      heart.stop()
      WKInterfaceDevice.current().play(.success)
    }
  }
}
