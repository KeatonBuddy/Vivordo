import HealthKit
import SwiftUI
import WatchConnectivity
import WatchKit

/// One minute of guided breathing, a tap on every turn of breath, then how the
/// heart rate settled. The result goes to the phone, which saves it.
struct ResetView: View {
  let next: WatchSnapshot.Event?
  let onDone: () -> Void

  @StateObject private var heart = HeartRateReader()
  @State private var secondsLeft = ResetView.total
  @State private var inhale = true
  @State private var finished = false
  @State private var startRate: Int?
  @State private var endRate: Int?

  static let total = 60
  private static let half = 5  // seconds in, seconds out
  private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      if finished { done } else { breathing }
    }
    .onAppear { heart.start() }
    .onDisappear { heart.stop() }
  }

  // MARK: Breathing

  private var breathing: some View {
    ZStack {
      Circle().fill(Color(white: 0.16)).frame(width: 150, height: 150)
      Circle().fill(Color(red: 0.33, green: 0.29, blue: 0.72)).frame(width: 150, height: 150)
        .scaleEffect(inhale ? 0.82 : 0.6)
      Circle().fill(WatchPalette.capacity).frame(width: 150, height: 150)
        .scaleEffect(inhale ? 0.6 : 0.36)
      VStack(spacing: 2) {
        Text(clock(secondsLeft))
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .monospacedDigit()
        Text(inhale ? "Breathe in" : "Breathe out")
          .font(.footnote.weight(.semibold))
      }
      .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.16))
    }
    .animation(.easeInOut(duration: Double(Self.half)), value: inhale)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .topLeading) {
      Text("Reset").font(.headline).foregroundStyle(WatchPalette.capacity).padding(.leading, 6)
    }
    .overlay(alignment: .bottom) {
      Text(next.map { "Before \($0.title)" } ?? "Press the crown to stop")
        .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1)
    }
    .onReceive(tick) { _ in step() }
    .onReceive(heart.$bpm) { bpm in
      if startRate == nil, let bpm { startRate = bpm }
    }
    .onAppear { WKInterfaceDevice.current().play(.directionUp) }
  }

  private func step() {
    // Hold the minute until Health has answered, so a first-time permission
    // sheet doesn't eat into it.
    guard !finished, heart.ready else { return }
    secondsLeft -= 1
    if secondsLeft <= 0 {
      finished = true
      endRate = heart.bpm
      heart.stop()
      WKInterfaceDevice.current().play(.success)
      send()
      return
    }
    if (Self.total - secondsLeft) % Self.half == 0 {
      inhale.toggle()
      WKInterfaceDevice.current().play(inhale ? .directionUp : .directionDown)
    }
  }

  // MARK: Done

  private var done: some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 44))
        .foregroundStyle(Color(red: 0.36, green: 0.79, blue: 0.65))
      Text("Reset done").font(.headline)
      Text(heartLine.title).font(.footnote).foregroundStyle(WatchPalette.secondary)
      if let detail = heartLine.detail {
        Text(detail).font(.footnote.weight(.semibold))
      }
      if let next, next.start > Date() {
        Text("\(next.title) in \(next.start, format: .relative(presentation: .numeric))")
          .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(2)
          .multilineTextAlignment(.center)
      }
      Button("Done", action: onDone).padding(.top, 4)
    }
    .padding(.horizontal, 4)
  }

  private var heartLine: (title: String, detail: String?) {
    switch (startRate, endRate) {
    case let (s?, e?) where s != e:
      return ("Heart rate \(e < s ? "settled" : "went up")", "\(s) → \(e) bpm")
    case let (_, e?): return ("Heart rate", "\(e) bpm")
    case let (s?, _): return ("Heart rate", "\(s) bpm")
    default: return ("No heart rate reading", nil)
    }
  }

  /// Goes to the phone as the watch's application context: the last day's
  /// resets, so one finished while the phone was away still arrives, and the
  /// phone (WatchSnapshotBridge) queues only those it hasn't seen.
  private func send() {
    let nowMs = Date().timeIntervalSince1970 * 1000
    var reset: [String: Any] = ["at": Int(nowMs), "seconds": Self.total]
    if let startRate { reset["hrStart"] = startRate }
    if let endRate { reset["hrEnd"] = endRate }
    let defaults = UserDefaults(suiteName: WatchSnapshot.appGroup)
    var recent = (defaults?.array(forKey: "watchResets") as? [[String: Any]] ?? [])
      .filter { (($0["at"] as? NSNumber)?.doubleValue ?? 0) > nowMs - 86_400_000 }
    recent.append(reset)
    defaults?.set(recent, forKey: "watchResets")
    do {
      try WCSession.default.updateApplicationContext(["watchResets": recent])
    } catch {
      NSLog("Vivordo watch: could not send the reset: \(error)")
    }
  }

  private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

/// Live heart rate from the watch's sensor. A mind-and-body workout session is
/// what makes the sensor read every few seconds; it is discarded at the end so
/// nothing lands in Health.
final class HeartRateReader: NSObject, ObservableObject, HKLiveWorkoutBuilderDelegate,
  HKWorkoutSessionDelegate
{
  @Published private(set) var bpm: Int?
  /// True once the sensor is running, or as soon as it is known it can't be.
  @Published private(set) var ready = false

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?

  func start() {
    guard session == nil else { return }
    guard HKHealthStore.isHealthDataAvailable() else { return ready = true }
    let heartRate = HKQuantityType(.heartRate)
    store.requestAuthorization(toShare: [.workoutType()], read: [heartRate]) { [weak self] ok, _ in
      DispatchQueue.main.async { self?.ready = true }
      guard ok, let self else { return }
      let config = HKWorkoutConfiguration()
      config.activityType = .mindAndBody
      config.locationType = .unknown
      do {
        let session = try HKWorkoutSession(healthStore: self.store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: self.store, workoutConfiguration: config)
        builder.delegate = self
        session.delegate = self
        self.session = session
        self.builder = builder
        session.startActivity(with: Date())
        builder.beginCollection(withStart: Date()) { _, _ in }
      } catch {
        NSLog("Vivordo watch: heart rate session failed: \(error)")
      }
    }
  }

  func stop() {
    guard let session, let builder else { return }
    session.end()
    builder.endCollection(withEnd: Date()) { _, _ in builder.discardWorkout() }
    self.session = nil
    self.builder = nil
  }

  // MARK: HKLiveWorkoutBuilderDelegate

  func workoutBuilder(_ builder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
    guard types.contains(HKQuantityType(.heartRate)),
          let value = builder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
    else { return }
    DispatchQueue.main.async { self.bpm = Int(value.rounded()) }
  }

  func workoutBuilderDidCollectEvent(_ builder: HKLiveWorkoutBuilder) {}

  // MARK: HKWorkoutSessionDelegate

  func workoutSession(
    _ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState,
    date: Date
  ) {}

  func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
    NSLog("Vivordo watch: heart rate session error: \(error)")
  }
}
