import ActivityKit
import AppIntents
import Flutter
import HealthKit
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let workoutActivities = WorkoutLiveActivityManager()
  private var workoutActivityChannel: FlutterMethodChannel?
  private var homeWidgetChannel: FlutterMethodChannel?
  private var vo2MaxChannel: FlutterMethodChannel?
  private let vo2MaxReader = Vo2MaxReader()
  private let sleepObserver = SleepObserver()
  private var pendingWorkoutLaunch = false
  private var pendingWidgetDestination: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      if isWorkoutActivityURL(url) {
        pendingWorkoutLaunch = true
      } else if let destination = widgetDestination(from: url) {
        pendingWidgetDestination = destination
      }
    }
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    // App Shortcut phrases are cached by iOS across app upgrades. Refresh the
    // catalog so renamed or corrected Siri phrases become active immediately.
    VivordoAppShortcuts.updateAppShortcutParameters()

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    // HealthKit only delivers in the background to queries started at launch.
    sleepObserver.start()

    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
      let channel = FlutterMethodChannel(
        name: "com.vivordo.health/workout_activity",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      workoutActivityChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleWorkoutActivity(call, result: result)
      }

      // VO₂ max (cardio fitness) from Apple Watch. The health plugin can't
      // read it, so it's read here (Physical Health, docs/scores.md).
      let vo2Channel = FlutterMethodChannel(
        name: "com.vivordo.health/vo2_max",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      vo2MaxChannel = vo2Channel
      vo2Channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "read",
              let days = (call.arguments as? [String: Any])?["days"] as? Int
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.vo2MaxReader.read(days: days) { samples in
          DispatchQueue.main.async { result(samples) }
        }
      }

      let sleepChannel = FlutterMethodChannel(
        name: "com.vivordo.health/sleep_observer",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      sleepChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "ready" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.sleepObserver.attach(sleepChannel)
        result(nil)
      }

      let widgetChannel = FlutterMethodChannel(
        name: "com.vivordo.health/home_widgets",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      homeWidgetChannel = widgetChannel
      widgetChannel.setMethodCallHandler { [weak self] call, result in
        if call.method == "consumeWidgetLaunch" {
          result(self?.pendingWidgetDestination)
          return
        }
        if call.method == "completeWidgetLaunch" {
          let destination = call.arguments as? String
          if destination == self?.pendingWidgetDestination {
            self?.pendingWidgetDestination = nil
          }
          result(nil)
          return
        }
        if call.method == "updateSnapshot",
           let values = call.arguments as? [String: Any] {
          let changedKeys = Set(values.keys)
          DispatchQueue.global(qos: .utility).async {
            guard let defaults = UserDefaults(suiteName: "group.com.vivordo.health") else {
              DispatchQueue.main.async { result(nil) }
              return
            }
            values.forEach { defaults.set($0.value, forKey: $0.key) }
            WidgetCenter.shared.reloadTimelines(ofKind: "VivordoDayDashboard")
            if !changedKeys.isDisjoint(with: ["dashboardEvents", "dashboardPriorities", "dashboardCalendarConnected"]) {
              WidgetCenter.shared.reloadTimelines(ofKind: "VivordoTodayAgenda")
            }
            defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")

            let stressKeys: Set<String> = ["stressScore"]
            let capacityKeys: Set<String> = [
              "capacityScore", "capacityDelta", "capacityLabel", "capacityNote",
              "capacityDay", "dashboardHasCapacity",
            ]
            let fitnessKeys: Set<String> = [
              "steps", "stepsGoal", "activeCalories", "activeCaloriesGoal",
              "exerciseMinutes", "exerciseGoal",
            ]
            let calendarKeys: Set<String> = ["calendarEvents"]

            if !changedKeys.isDisjoint(with: stressKeys) {
              WidgetCenter.shared.reloadTimelines(ofKind: "VivordoStressScore")
            }
            if !changedKeys.isDisjoint(with: capacityKeys) {
              WidgetCenter.shared.reloadTimelines(ofKind: "VivordoWellnessScore")
            }
            if !changedKeys.isDisjoint(with: fitnessKeys) {
              WidgetCenter.shared.reloadTimelines(ofKind: "VivordoFitnessRings")
            }
            if !changedKeys.isDisjoint(with: calendarKeys) {
              WidgetCenter.shared.reloadTimelines(ofKind: "VivordoCalendar")
            }

            DispatchQueue.main.async { result(nil) }
          }
          return
        }
        result(FlutterMethodNotImplemented)
      }
  }

  private func deliverPendingWidgetDestination() {
    guard let destination = pendingWidgetDestination,
          let homeWidgetChannel else { return }
    homeWidgetChannel.invokeMethod("widgetTapped", arguments: destination) { [weak self] result in
      if result as? Bool == true,
         self?.pendingWidgetDestination == destination {
        self?.pendingWidgetDestination = nil
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleVivordoURL(url) { return true }
    return super.application(app, open: url, options: options)
  }

  @discardableResult
  func handleVivordoURL(_ url: URL, notify: Bool = true) -> Bool {
    if let destination = widgetDestination(from: url) {
      pendingWidgetDestination = destination
      if notify { homeWidgetChannel?.invokeMethod("widgetTapped", arguments: destination) }
      return true
    }
    guard isWorkoutActivityURL(url) else {
      return false
    }
    pendingWorkoutLaunch = true
    if notify { workoutActivityChannel?.invokeMethod("workoutActivityTapped", arguments: nil) }
    return true
  }

  private func isWorkoutActivityURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "com.vivordo.health" &&
      url.host?.lowercased() == "fitness"
  }

  private func widgetDestination(from url: URL) -> String? {
    guard url.scheme?.lowercased() == "com.vivordo.health",
          url.host?.lowercased() == "widget" else {
      return nil
    }
    let destination = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    return [
      "home", "capacity", "fitness", "calendar", "myday", "mood", "workout",
      "stress", "sleep", "heartrate", "steps"
    ].contains(destination) ? destination : nil
  }

  private func handleWorkoutActivity(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "consumeWorkoutLaunch" {
      let shouldOpen = pendingWorkoutLaunch
      pendingWorkoutLaunch = false
      result(shouldOpen)
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeTitle = title?.isEmpty == false ? title! : "Workout"
    let exerciseCount = arguments["exerciseCount"] as? Int ?? 0

    Task {
      do {
        switch call.method {
        case "start":
          guard let startedAtMilliseconds = arguments["startedAt"] as? NSNumber else {
            throw WorkoutActivityError.invalidStartDate
          }
          let startedAt = Date(
            timeIntervalSince1970: startedAtMilliseconds.doubleValue / 1000
          )
          try await workoutActivities.start(
            startedAt: startedAt,
            title: safeTitle,
            exerciseCount: exerciseCount
          )
        case "update":
          await workoutActivities.update(title: safeTitle, exerciseCount: exerciseCount)
        case "end":
          await workoutActivities.end()
        default:
          await MainActor.run { result(FlutterMethodNotImplemented) }
          return
        }
        await MainActor.run { result(nil) }
      } catch {
        await MainActor.run {
          result(
            FlutterError(
              code: "workout_activity_error",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}

// Kept in this compiled source file so both device and simulator targets include it.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Queue cold-start destinations before Flutter initializes its channels.
    let app = UIApplication.shared.delegate as? AppDelegate
    for context in connectionOptions.urlContexts {
      app?.handleVivordoURL(context.url, notify: false)
    }
    // Preserve Flutter/plugin delivery, including authentication callbacks.
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let app = UIApplication.shared.delegate as? AppDelegate
    let remaining = Set(URLContexts.filter { app?.handleVivordoURL($0.url) != true })
    if !remaining.isEmpty { super.scene(scene, openURLContexts: remaining) }
  }
}

/// Reads Apple Watch VO₂ max samples. Asks for read access the first time
/// (HealthKit shows its sheet once); returns [] when unavailable or denied,
/// since HealthKit never reveals whether read access was refused.
private final class Vo2MaxReader {
  private let store = HKHealthStore()
  private let type = HKQuantityType(.vo2Max)
  private let unit = HKUnit(from: "ml/kg*min")

  func read(days: Int, completion: @escaping ([[String: Any]]) -> Void) {
    guard HKHealthStore.isHealthDataAvailable() else { return completion([]) }
    store.requestAuthorization(toShare: [], read: [type]) { [weak self] _, _ in
      guard let self else { return completion([]) }
      let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
      let predicate = HKQuery.predicateForSamples(
        withStart: start, end: Date(), options: .strictStartDate
      )
      let query = HKSampleQuery(
        sampleType: self.type,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
      ) { _, samples, _ in
        completion((samples as? [HKQuantitySample] ?? []).map {
          [
            "date": $0.endDate.timeIntervalSince1970 * 1000,
            "value": $0.quantity.doubleValue(for: self.unit),
          ]
        })
      }
      self.store.execute(query)
    }
  }
}

/// Wakes Vivordo when new sleep reaches the iPhone's Health store (from
/// Apple Watch, or any app writing sleep), so last night shows up without
/// opening Apple Health. Dart syncs it (HealthService.listenForNewSleep).
/// HealthKit stops waking an app that doesn't call the completion handler,
/// so each one is called when Dart replies, or after 25 seconds at most.
private final class SleepObserver {
  private let store = HKHealthStore()
  private let type = HKCategoryType(.sleepAnalysis)
  private var channel: FlutterMethodChannel?
  private var waiting: [() -> Void] = []
  private var syncing = false

  func start() {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    let query = HKObserverQuery(sampleType: type, predicate: nil) {
      [weak self] _, completion, error in
      DispatchQueue.main.async {
        guard let self, error == nil else { return completion() }
        var called = false
        let done = {
          guard !called else { return }
          called = true
          completion()
        }
        self.waiting.append(done)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: done)
        self.syncIfReady()
      }
    }
    store.execute(query)
    store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
  }

  /// Called once Dart has its handler, which may be after the first wake.
  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    syncIfReady()
  }

  private func syncIfReady() {
    guard let channel, !syncing, !waiting.isEmpty else { return }
    syncing = true
    let batch = waiting
    waiting = []
    channel.invokeMethod("sleepChanged", arguments: nil) { [weak self] _ in
      batch.forEach { $0() }
      self?.syncing = false
      self?.syncIfReady()
    }
  }
}

private enum WorkoutActivityError: LocalizedError {
  case invalidStartDate
  case activitiesDisabled

  var errorDescription: String? {
    switch self {
    case .invalidStartDate:
      return "The workout start date was invalid."
    case .activitiesDisabled:
      return "Live Activities are disabled for Vivordo."
    }
  }
}

@available(iOS 16.1, *)
private final class WorkoutLiveActivityManager {
  private var lastAppliedState: WorkoutActivityAttributes.ContentState?

  private func state(title: String, exerciseCount: Int) -> WorkoutActivityAttributes.ContentState {
    WorkoutActivityAttributes.ContentState(
      title: title,
      exerciseCount: exerciseCount,
      status: "Workout in progress"
    )
  }

  func start(startedAt: Date, title: String, exerciseCount: Int) async throws {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw WorkoutActivityError.activitiesDisabled
    }

    let contentState = state(title: title, exerciseCount: exerciseCount)
    if let existing = Activity<WorkoutActivityAttributes>.activities.first {
      await existing.update(using: contentState)
      lastAppliedState = contentState
      return
    }

    let attributes = WorkoutActivityAttributes(startedAt: startedAt)
    _ = try Activity.request(
      attributes: attributes,
      contentState: contentState,
      pushType: nil
    )
    lastAppliedState = contentState
  }

  func update(title: String, exerciseCount: Int) async {
    let contentState = state(title: title, exerciseCount: exerciseCount)
    // Skip redundant ActivityKit calls when nothing actually changed —
    // each update consumes part of iOS's per-Live-Activity update budget.
    guard contentState != lastAppliedState else { return }
    for activity in Activity<WorkoutActivityAttributes>.activities {
      await activity.update(using: contentState)
    }
    lastAppliedState = contentState
  }

  func end() async {
    let finalState = WorkoutActivityAttributes.ContentState(
      title: "Workout complete",
      exerciseCount: 0,
      status: "Finished"
    )
    for activity in Activity<WorkoutActivityAttributes>.activities {
      await activity.end(using: finalState, dismissalPolicy: .immediate)
    }
    lastAppliedState = nil
  }
}
