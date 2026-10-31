import SwiftUI

@main
struct VivordoWatchApp: App {
  @StateObject private var store = WatchSnapshotStore.shared
  @StateObject private var resets = ResetScheduler.shared

  init() { ResetScheduler.shared.start() }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        TodayView()
      }
      .environmentObject(store)
      .environmentObject(resets)
      .sheet(isPresented: $resets.resetRequested) {
        ResetView(next: store.snapshot?.nextEvent) { resets.resetRequested = false }
      }
    }
  }
}
