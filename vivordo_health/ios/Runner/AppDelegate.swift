import ActivityKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let workoutActivities = WorkoutLiveActivityManager()
  private var workoutActivityChannel: FlutterMethodChannel?
  private var pendingWorkoutLaunch = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL, isWorkoutActivityURL(url) {
      pendingWorkoutLaunch = true
    }
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.vivordo.health/workout_activity",
        binaryMessenger: controller.binaryMessenger
      )
      workoutActivityChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handleWorkoutActivity(call, result: result)
      }
    }

    return launched
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard isWorkoutActivityURL(url) else {
      return super.application(app, open: url, options: options)
    }
    pendingWorkoutLaunch = true
    workoutActivityChannel?.invokeMethod("workoutActivityTapped", arguments: nil)
    return true
  }

  private func isWorkoutActivityURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "com.vivordo.health" &&
      url.host?.lowercased() == "fitness"
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
      return
    }

    let attributes = WorkoutActivityAttributes(startedAt: startedAt)
    _ = try Activity.request(
      attributes: attributes,
      contentState: contentState,
      pushType: nil
    )
  }

  func update(title: String, exerciseCount: Int) async {
    let contentState = state(title: title, exerciseCount: exerciseCount)
    for activity in Activity<WorkoutActivityAttributes>.activities {
      await activity.update(using: contentState)
    }
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
  }
}
