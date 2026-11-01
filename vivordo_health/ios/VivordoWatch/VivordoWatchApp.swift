import SwiftUI

@main
struct VivordoWatchApp: App {
  @StateObject private var store = WatchSnapshotStore.shared
  @StateObject private var resets = ResetScheduler.shared
  @StateObject private var workout = WorkoutSession.shared

  init() { ResetScheduler.shared.start() }

  var body: some Scene {
    WindowGroup {
      // A workout takes over the app until Done, as Apple's Workout app does.
      Group {
        if workout.isActive {
          WorkoutView()
        } else {
          NavigationStack {
            TodayView()
          }
        }
      }
      .environmentObject(store)
      .environmentObject(resets)
      .environmentObject(workout)
      .sheet(isPresented: $resets.resetRequested) {
        ResetView(next: store.snapshot?.nextEvent) { resets.resetRequested = false }
      }

    }
  }
}
