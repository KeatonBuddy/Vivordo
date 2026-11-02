import SwiftUI
import WatchKit

/// Today's priorities, a tap ticks one off and the phone saves it, then the
/// day's timeline: meetings and timed priorities in order, with a Now line.
struct MyDayView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @State private var ticked = WatchActions.tickedIds

  var body: some View {
    let priorities = store.snapshot?.priorities ?? []
    let now = Date()
    List {
      Section("Priorities") {
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

      Section("Today's timeline") {
        let items = timeline(priorities, now: now)
        if items.isEmpty {
          Text("Nothing timed today")
            .font(.footnote)
            .foregroundStyle(WatchPalette.secondary)
        }
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          if item.isNow {
            HStack(spacing: 6) {
              Text("Now").font(.caption2.weight(.bold)).foregroundStyle(Self.nowColor)
              Rectangle().fill(Self.nowColor).frame(height: 1.5)
            }
            .listRowBackground(Color.clear)
          } else {
            HStack(alignment: .top, spacing: 6) {
              Text(item.start, format: .dateTime.hour(.defaultDigits(amPM: .narrow)).minute())
                .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(WatchPalette.secondary)
                .frame(width: 46, alignment: .leading)
              Text(item.title).font(.footnote).lineLimit(2)
            }
            .opacity(item.end < now ? 0.45 : 1)
          }
        }
      }
    }
    .navigationTitle("My Day")
  }

  private static let nowColor = Color(red: 0.91, green: 0.38, blue: 0.24)

  private struct Item {
    let start: Date
    let end: Date
    let title: String
    var isNow = false
  }

  /// Today's meetings and timed priorities by start, with a Now marker
  /// between what has started and what hasn't.
  private func timeline(_ priorities: [WatchSnapshot.Priority], now: Date) -> [Item] {
    let calendar = Calendar.current
    var items = (store.snapshot?.events ?? [])
      .filter { calendar.isDate($0.start, inSameDayAs: now) }
      .map { Item(start: $0.start, end: $0.end, title: $0.title) }
    items += priorities.compactMap { p in
      p.start.map { Item(start: $0, end: $0.addingTimeInterval(30 * 60), title: p.title) }
    }
    items.sort { $0.start < $1.start }
    guard !items.isEmpty else { return [] }
    let index = items.firstIndex { $0.start > now } ?? items.count
    items.insert(Item(start: now, end: now, title: "", isNow: true), at: index)
    return items
  }

  /// One way only: unticking stays on the phone.
  private func tick(_ priority: WatchSnapshot.Priority, in priorities: [WatchSnapshot.Priority]) {
    ticked.insert(priority.id)
    WatchActions.tickedIds = ticked.intersection(priorities.map(\.id))
    WKInterfaceDevice.current().play(.success)
    WatchActions.send("taskDone", ["priorityId": priority.id, "day": WatchSnapshot.dayKey(Date())])
  }
}
