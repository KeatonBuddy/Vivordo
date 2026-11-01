import Foundation
import HealthKit
import WatchKit

/// One workout on the wrist: a real workout session that is saved to Health,
/// the sets logged along the way, and the result sent to the phone (action
/// kind "workout"), which saves it with the phone's own workouts.
final class WorkoutSession: NSObject, ObservableObject, HKWorkoutSessionDelegate,
  HKLiveWorkoutBuilderDelegate
{
  static let shared = WorkoutSession()

  enum Kind: Equatable {
    case strength, run, walk, cycle

    var isCardio: Bool { self != .strength }

    fileprivate var activityType: HKWorkoutActivityType {
      switch self {
      case .strength: .traditionalStrengthTraining
      case .run: .running
      case .walk: .walking
      case .cycle: .cycling
      }
    }

    fileprivate var distanceType: HKQuantityType? {
      switch self {
      case .strength: nil
      case .run, .walk: HKQuantityType(.distanceWalkingRunning)
      case .cycle: HKQuantityType(.distanceCycling)
      }
    }
  }

  struct LoggedSet {
    let weight: Double
    let reps: Int
    let at: Date
  }

  struct Exercise: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let targetSets: Int?
    /// Last time's sets, from the phone.
    let last: [WatchSnapshot.Workout.Exercise.Set]
    var sets: [LoggedSet] = []
  }

  struct Summary {
    let name: String
    let kind: Kind
    let seconds: Int
    let calories: Int
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let sets: Int
    let km: Double
    /// Seconds in zones 1–5.
    let zoneSeconds: [Double]
  }

  static let restSeconds = 75

  /// True from Start until Done on the summary; shows the workout screens.
  @Published private(set) var isActive = false
  @Published private(set) var name = ""
  @Published private(set) var kind = Kind.strength
  @Published private(set) var exercises: [Exercise] = []
  @Published private(set) var current = 0
  @Published private(set) var paused = false
  @Published private(set) var bpm: Int?
  @Published private(set) var calories = 0.0
  @Published private(set) var km = 0.0
  @Published private(set) var restEnds: Date?
  @Published private(set) var restLength = WorkoutSession.restSeconds
  @Published private(set) var summary: Summary?
  /// Nil while Health is still saving the finished workout.
  @Published private(set) var savedToHealth: Bool?

  private let store = HKHealthStore()
  private var session: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?
  private var startDate: Date?
  private var restTimer: Timer?
  private var heartRateSum = 0.0
  private var heartRateCount = 0
  private var heartRateMax = 0
  private var zoneSeconds = [Double](repeating: 0, count: 5)
  private var lastHeartRateAt: Date?
  /// 220 minus age from Health's date of birth, else 190.
  /// ponytail: % of max heart rate zones; heart rate reserve if they feel off.
  private var maxHeartRate = 190.0

  private static let heartRate = HKQuantityType(.heartRate)
  private static let energy = HKQuantityType(.activeEnergyBurned)

  // MARK: Start, pause, end

  func start(name: String, kind: Kind, exercises: [Exercise]) {
    guard !isActive else { return }
    self.name = name
    self.kind = kind
    self.exercises = exercises
    current = 0
    paused = false
    bpm = nil
    calories = 0
    km = 0
    restEnds = nil
    summary = nil
    savedToHealth = nil
    heartRateSum = 0
    heartRateCount = 0
    heartRateMax = 0
    zoneSeconds = [Double](repeating: 0, count: 5)
    lastHeartRateAt = nil
    startDate = Date()
    isActive = true
    WKInterfaceDevice.current().play(.start)

    let distance: Set<HKQuantityType> = [
      HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
    ]
    let share: Set<HKSampleType> = Set([HKObjectType.workoutType(), Self.energy]).union(distance)
    let read: Set<HKObjectType> = Set([Self.heartRate, Self.energy, HKCharacteristicType(.dateOfBirth)])
      .union(distance)
    store.requestAuthorization(toShare: share, read: read) { [weak self] _, _ in
      DispatchQueue.main.async { self?.begin() }
    }
  }

  private func begin() {
    guard isActive, session == nil else { return }
    if let born = try? store.dateOfBirthComponents().date,
       let age = Calendar.current.dateComponents([.year], from: born, to: Date()).year,
       age > 10 {
      maxHeartRate = Double(220 - age)
    }
    let config = HKWorkoutConfiguration()
    config.activityType = kind.activityType
    config.locationType = kind.isCardio ? .outdoor : .indoor
    do {
      let session = try HKWorkoutSession(healthStore: store, configuration: config)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
      session.delegate = self
      builder.delegate = self
      self.session = session
      self.builder = builder
      let now = Date()
      startDate = now
      session.startActivity(with: now)
      builder.beginCollection(withStart: now) { _, _ in }
    } catch {
      // Sets can still be logged and sent; only Health and heart rate miss out.
      NSLog("Vivordo watch: workout session failed: \(error)")
    }
  }

  func togglePause() {
    guard let session else { return paused.toggle() }
    paused ? session.resume() : session.pause()
  }

  /// Time moving, pauses left out.
  func elapsed(at date: Date = Date()) -> TimeInterval {
    if let builder { return builder.elapsedTime(at: date) }
    return startDate.map { max(0, date.timeIntervalSince($0)) } ?? 0
  }

  /// Shows the summary and sends the workout to the phone straight away;
  /// Health saves it in the background.
  func end() {
    guard isActive, summary == nil, let startDate else { return }
    let end = Date()
    let seconds = Int(elapsed(at: end))
    stopRest()
    session?.end()
    finish(start: startDate, end: end, seconds: seconds)
    guard let builder else { return savedToHealth = false }
    builder.endCollection(withEnd: end) { [weak self] _, _ in
      // ponytail: under half a minute is an accidental start; nothing is kept.
      guard seconds >= 30 else {
        builder.discardWorkout()
        DispatchQueue.main.async { self?.savedToHealth = false }
        return
      }
      builder.finishWorkout { workout, error in
        if let error { NSLog("Vivordo watch: workout not saved to Health: \(error)") }
        DispatchQueue.main.async { self?.savedToHealth = workout != nil }
      }
    }
  }

  /// Done on the summary.
  func close() {
    isActive = false
    summary = nil
    savedToHealth = nil
    session = nil
    builder = nil
  }

  private func finish(start: Date, end: Date, seconds: Int) {
    let logged = exercises.reduce(0) { $0 + $1.sets.count }
    summary = Summary(
      name: name, kind: kind, seconds: seconds, calories: Int(calories.rounded()),
      averageHeartRate: heartRateCount > 0 ? Int((heartRateSum / Double(heartRateCount)).rounded()) : nil,
      maxHeartRate: heartRateMax > 0 ? heartRateMax : nil,
      sets: logged, km: km, zoneSeconds: zoneSeconds
    )
    WKInterfaceDevice.current().play(.success)
    guard seconds >= 30 else { return }
    WatchActions.send("workout", [
      "name": name,
      // Int64: Int is 32 bits on arm64_32 watches.
      "startAt": Int64(start.timeIntervalSince1970 * 1000),
      "endAt": Int64(end.timeIntervalSince1970 * 1000),
      "seconds": seconds,
      "exercises": payloadExercises(),
    ])
  }

  /// Strength exercises with no sets are left out, as the phone does.
  private func payloadExercises() -> [[String: Any]] {
    if kind.isCardio {
      var run: [String: Any] = ["name": name.cardioExerciseName, "category": kind == .cycle ? "Sports" : "Cardio", "sets": [[String: Any]]()]
      if km > 0 { run["km"] = km }
      return [run]
    }
    return exercises.filter { !$0.sets.isEmpty }.map { exercise in
      [
        "name": exercise.name,
        "category": exercise.category,
        "sets": exercise.sets.map {
          ["w": $0.weight, "r": $0.reps, "at": Int64($0.at.timeIntervalSince1970 * 1000)] as [String: Any]
        },
      ]
    }
  }

  // MARK: Sets and rest

  func logSet(weight: Double, reps: Int) {
    guard exercises.indices.contains(current) else { return }
    exercises[current].sets.append(LoggedSet(weight: weight, reps: reps, at: Date()))
    WKInterfaceDevice.current().play(.click)
    if let target = exercises[current].targetSets, exercises[current].sets.count >= target,
       current < exercises.count - 1 {
      current += 1
    }
    startRest()
  }

  func nextExercise() {
    if current < exercises.count - 1 { current += 1 }
  }

  func addExercise(_ name: String) {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    exercises.append(Exercise(name: clean, category: "Other", targetSets: nil, last: []))
    current = exercises.count - 1
  }

  func startRest(seconds: Int = WorkoutSession.restSeconds) {
    restLength = seconds
    scheduleRest(until: Date().addingTimeInterval(TimeInterval(seconds)))
  }

  func addRest(_ seconds: Int) {
    guard let restEnds else { return }
    restLength += seconds
    scheduleRest(until: restEnds.addingTimeInterval(TimeInterval(seconds)))
  }

  func stopRest() {
    restTimer?.invalidate()
    restTimer = nil
    restEnds = nil
  }

  private func scheduleRest(until end: Date) {
    restTimer?.invalidate()
    restEnds = end
    restTimer = Timer.scheduledTimer(withTimeInterval: max(0, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
      WKInterfaceDevice.current().play(.notification)
      self?.stopRest()
    }
  }

  /// Zone 1–5 as 0–4: under 60% of max, then 10% bands.
  func zone(_ bpm: Int) -> Int {
    min(4, max(0, Int((Double(bpm) / maxHeartRate - 0.5) / 0.1)))
  }

  // MARK: HKWorkoutSessionDelegate

  func workoutSession(
    _ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState,
    date: Date
  ) {
    DispatchQueue.main.async { self.paused = to == .paused }
  }

  func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) {
    NSLog("Vivordo watch: workout session error: \(error)")
  }

  // MARK: HKLiveWorkoutBuilderDelegate

  func workoutBuilder(_ builder: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
    let rate = types.contains(Self.heartRate)
      ? builder.statistics(for: Self.heartRate)?.mostRecentQuantity()?
        .doubleValue(for: .count().unitDivided(by: .minute()))
      : nil
    let energy = builder.statistics(for: Self.energy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    let distance = kind.distanceType.flatMap {
      builder.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
    }
    DispatchQueue.main.async {
      if let energy { self.calories = energy }
      if let distance { self.km = distance }
      guard let rate else { return }
      let now = Date()
      if let previous = self.bpm, let at = self.lastHeartRateAt, !self.paused {
        // Readings come every few seconds; a gap longer than 10 s isn't counted.
        self.zoneSeconds[self.zone(previous)] += min(10, now.timeIntervalSince(at))
      }
      let value = Int(rate.rounded())
      self.bpm = value
      self.lastHeartRateAt = now
      self.heartRateSum += rate
      self.heartRateCount += 1
      self.heartRateMax = max(self.heartRateMax, value)
    }
  }

  func workoutBuilderDidCollectEvent(_ builder: HKLiveWorkoutBuilder) {}
}

private extension String {
  /// The phone's exercise for a cardio workout ("Outdoor run" → "Run").
  var cardioExerciseName: String {
    let lower = lowercased()
    if lower.contains("walk") { return "Walk" }
    if lower.contains("cycl") { return "Cycling" }
    return "Run"
  }
}
