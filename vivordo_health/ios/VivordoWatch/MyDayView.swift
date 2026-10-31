import SwiftUI
import WatchKit

/// Today's priorities; a tap ticks one off, and the phone saves it.
struct MyDayView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @State private var ticked = WatchActions.tickedIds

  var body: some View {
    let priorities = store.snapshot?.priorities ?? []
    List {
      if priorities.isEmpty {
        Text("No priorities today")
          .font(.footnote)
          .foregroundStyle(WatchPalette.secondary)
      }
      ForEach(priorities) { priority in
        let done = priority.completed || ticked.contains(priority.id)
        Button {
          tick(priority, in: priorities)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(done ? WatchPalette.capacity : WatchPalette.secondary)
            VStack(alignment: .leading, spacing: 1) {
              Text(priority.title)
                .font(.footnote.weight(.semibold))
                .strikethrough(done)
                .foregroundStyle(done ? WatchPalette.secondary : .primary)
                .lineLimit(2)
              Text(priority.time).font(.caption2).foregroundStyle(WatchPalette.secondary)
            }
          }
        }
        .disabled(done)
      }
    }
    .navigationTitle("My Day")
  }

  /// One way only: unticking stays on the phone.
  private func tick(_ priority: WatchSnapshot.Priority, in priorities: [WatchSnapshot.Priority]) {
    ticked.insert(priority.id)
    WatchActions.tickedIds = ticked.intersection(priorities.map(\.id))
    WKInterfaceDevice.current().play(.success)
    WatchActions.send("taskDone", ["priorityId": priority.id, "day": WatchSnapshot.dayKey(Date())])
  }
}
