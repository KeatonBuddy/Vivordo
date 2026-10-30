import SwiftUI

@main
struct VivordoWatchApp: App {
  @StateObject private var store = WatchSnapshotStore.shared

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        TodayView()
      }
      .environmentObject(store)
    }
  }
}
