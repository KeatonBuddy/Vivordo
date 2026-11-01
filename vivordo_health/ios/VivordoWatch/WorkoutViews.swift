import SwiftUI

private let fitness = Color(red: 0.36, green: 0.79, blue: 0.65)
private let calorie = Color(red: 0.94, green: 0.63, blue: 0.19)
private let zoneColors: [Color] = [
  WatchPalette.demand, fitness, calorie, WatchPalette.stress, Color(red: 0.88, green: 0.27, blue: 0.48),
]

/// Workout row on Today: the phone's saved workouts, quick cardio, an empty one.
struct WorkoutStartView: View {
  @EnvironmentObject private var store: WatchSnapshotStore
  @EnvironmentObject private var workout: WorkoutSession
  /// Pops this list once the workout screens are up.
  let onStart: () -> Void

  var body: some View {
    List {
      if let line = capacityLine {
        Text(line).font(.caption2).foregroundStyle(WatchPalette.secondary).listRowBackground(Color.clear)
      }
      ForEach(store.snapshot?.workouts ?? []) { saved in
        Button {
          start(saved.name, .strength, saved.exercises.map {
            .init(name: $0.name, category: $0.category, targetSets: $0.targetSets, last: $0.last)
          })
        } label: {
          row(saved.name, "\(saved.exercises.count) exercise\(saved.exercises.count == 1 ? "" : "s")",
              icon: "dumbbell.fill", color: fitness)
        }
      }
      Button { start("Outdoor run", .run, []) } label: {
        row("Outdoor run", nil, icon: "figure.run", color: WatchPalette.demand)
      }
      Button { start("Outdoor walk", .walk, []) } label: {
        row("Outdoor walk", nil, icon: "figure.walk", color: WatchPalette.demand)
      }
      Button { start("Outdoor cycle", .cycle, []) } label: {
        row("Outdoor cycle", nil, icon: "figure.outdoor.cycle", color: WatchPalette.demand)
      }
      Button { start("Workout", .strength, []) } label: {
        row("Empty workout", nil, icon: "plus", color: WatchPalette.secondary)
      }
    }
    .navigationTitle("Workout")
  }

  /// A nudge from today's Capacity, never a block.
  private var capacityLine: String? {
    guard let score = store.snapshot?.capacityScore else { return nil }
    let fits = score >= 80 ? "a hard session fits" : score >= 50 ? "a moderate session fits" : "an easy session fits"
    return "Capacity \(score) · \(fits)"
  }

  private func start(_ name: String, _ kind: WorkoutSession.Kind, _ exercises: [WorkoutSession.Exercise]) {
    workout.start(name: name, kind: kind, exercises: exercises)
    onStart()
  }

  private func row(_ title: String, _ detail: String?, icon: String, color: Color) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(color).frame(width: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.body.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        if let detail {
          Text(detail).font(.caption2).foregroundStyle(WatchPalette.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

/// Everything from Start to Done, over the rest of the app: swipe right for
/// the controls; the summary when it ends.
struct WorkoutView: View {
  @EnvironmentObject private var workout: WorkoutSession
  @State private var page = 1
  // Here, not on the pages: rest swaps the page out while Log set is open.
  @State private var logging = false
  @State private var adding = false

  var body: some View {
    NavigationStack {
      if let summary = workout.summary {
        WorkoutSummaryView(summary: summary)
      } else {
        TabView(selection: $page) {
          WorkoutControlsView { adding = true }.tag(0)
          Group {
            if workout.restEnds != nil {
              RestView()
            } else if workout.kind.isCardio {
              CardioView()
            } else {
              StrengthView(onLog: { logging = true }, onAdd: { adding = true })
            }
          }
          .tag(1)
        }
        .tabViewStyle(.page)
        .onChange(of: workout.current) { page = 1 }
        .navigationDestination(isPresented: $logging) { LogSetView { logging = false } }
        .navigationDestination(isPresented: $adding) {
          AddExerciseView {
            adding = false
            page = 1
          }
        }
      }
    }
  }
}

// MARK: In progress

private struct Header: View {
  @EnvironmentObject private var workout: WorkoutSession
  let color: Color

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(workout.name).font(.footnote.weight(.semibold)).foregroundStyle(color).lineLimit(1)
      Spacer(minLength: 4)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(clock(workout.elapsed(at: context.date)))
          .font(.footnote.weight(.semibold).monospacedDigit())
          .foregroundStyle(workout.paused ? calorie : .white)
      }
    }
  }
}

private struct HeartRateLine: View {
  @EnvironmentObject private var workout: WorkoutSession

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "heart.fill").foregroundStyle(WatchPalette.stress)
      Text(workout.bpm.map(String.init) ?? "--")
        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
        .fixedSize()
      VStack(alignment: .leading, spacing: 0) {
        Text("bpm").font(.caption2).foregroundStyle(WatchPalette.secondary).fixedSize()
        if let bpm = workout.bpm {
          let zone = workout.zone(bpm)
          Text("Zone \(zone + 1)").font(.caption2.weight(.semibold)).foregroundStyle(zoneColors[zone])
            .fixedSize()
        }
      }
    }
  }
}

private struct StrengthView: View {
  @EnvironmentObject private var workout: WorkoutSession
  let onLog: () -> Void
  let onAdd: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Header(color: fitness)
        HStack {
          HeartRateLine()
          Spacer(minLength: 4)
          Text("\(Int(workout.calories.rounded())) cal")
            .font(.caption2)
            .foregroundStyle(WatchPalette.secondary)
            .fixedSize()
        }
        if workout.exercises.indices.contains(workout.current) {
          let exercise = workout.exercises[workout.current]
          VStack(alignment: .leading, spacing: 1) {
            Text(setLine(exercise)).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
            Text(exercise.name).font(.headline).lineLimit(2)
            Text(lastLine(exercise)).font(.caption2).foregroundStyle(WatchPalette.secondary)
              .lineLimit(1).minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
          HStack(spacing: 6) {
            Button { workout.startRest() } label: {
              Label(clock(TimeInterval(WorkoutSession.restSeconds)), systemImage: "timer")
                .font(.footnote.weight(.semibold))
            }
            .tint(WatchPalette.capacity)
            Button("Log set", action: onLog)
              .font(.footnote.weight(.semibold))
          }
        } else {
          Text("Add an exercise to log sets, or just keep moving.")
            .font(.footnote).foregroundStyle(WatchPalette.secondary)
          Button("Add exercise", action: onAdd).font(.footnote.weight(.semibold))
        }
      }
      .scenePadding(.horizontal)
    }
  }

  private func setLine(_ e: WorkoutSession.Exercise) -> String {
    let next = e.sets.count + 1
    if let target = e.targetSets { return "Now · set \(min(next, target)) of \(target)" }
    return "Now · set \(next)"
  }

  private func lastLine(_ e: WorkoutSession.Exercise) -> String {
    if let set = e.sets.last { return "Last set \(pounds(set.weight)) lb × \(set.reps)" }
    if let set = e.last.first { return "Last time \(pounds(set.weight)) lb × \(set.reps)" }
    return "First time"
  }
}

private struct CardioView: View {
  @EnvironmentObject private var workout: WorkoutSession

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        Text(workout.name).font(.footnote.weight(.semibold)).foregroundStyle(WatchPalette.demand).lineLimit(1)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let elapsed = workout.elapsed(at: context.date)
          VStack(alignment: .leading, spacing: 2) {
            Text(clock(elapsed))
              .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
              .foregroundStyle(workout.paused ? calorie : Color(red: 0.94, green: 0.82, blue: 0.38))
            metric(String(format: "%.2f", workout.km), "km", size: 28)
            metric(pace(elapsed), workout.kind == .cycle ? "km/h avg" : "/km avg", size: 22)
          }
        }
        HeartRateLine()
        ZoneBar(active: workout.bpm.map(workout.zone))
          .padding(.top, 4)
      }
      .scenePadding(.horizontal)
    }
  }

  private func metric(_ value: String, _ unit: String, size: CGFloat) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Text(value).font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
      Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
    }
  }

  private func pace(_ elapsed: TimeInterval) -> String {
    guard workout.km > 0.05 else { return "--" }
    if workout.kind == .cycle { return String(format: "%.1f", workout.km / (elapsed / 3600)) }
    return clock(elapsed / workout.km)
  }
}

private struct ZoneBar: View {
  let active: Int?

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<5, id: \.self) { zone in
        Capsule()
          .fill(zone == active ? zoneColors[zone] : zoneColors[zone].opacity(0.3))
          .frame(height: zone == active ? 7 : 5)
      }
    }
    .accessibilityLabel(active.map { "Heart rate zone \($0 + 1) of 5" } ?? "No heart rate yet")
  }
}

/// Weight and reps, prefilled from this workout's last set or last time's.
private struct LogSetView: View {
  @EnvironmentObject private var workout: WorkoutSession
  let onDone: () -> Void
  private enum Field { case weight, reps }
  @State private var weight = 0.0
  @State private var reps = 8.0
  @FocusState private var focus: Field?

  var body: some View {
    let exercise = workout.exercises.indices.contains(workout.current)
      ? workout.exercises[workout.current] : nil
    // No ScrollView: the crown turns the numbers, not the page.
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          box("Weight", pounds(weight), "lb", selected: focus == .weight)
            .onTapGesture { focus = .weight }
            .focusable()
            .focused($focus, equals: .weight)
            .digitalCrownRotation($weight, from: 0, through: 1000, by: 5, sensitivity: .medium,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
          box("Reps", "\(Int(reps))", "reps", selected: focus == .reps)
            .onTapGesture { focus = .reps }
            .focusable()
            .focused($focus, equals: .reps)
            .digitalCrownRotation($reps, from: 0, through: 100, by: 1, sensitivity: .medium,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
        }
        if let set = exercise?.last.first {
          Text("\(exercise?.name ?? "") · last \(pounds(set.weight)) × \(set.reps)").font(.caption2)
            .foregroundStyle(WatchPalette.secondary)
            .lineLimit(2)
        }
        Button("Log set · rest \(clock(TimeInterval(WorkoutSession.restSeconds)))") {
          workout.logSet(weight: weight, reps: Int(reps))
          onDone()
        }
        .font(.footnote.weight(.semibold))
        .tint(WatchPalette.capacity)
        .disabled(reps < 1)
    }
    .scenePadding(.horizontal)
    .navigationTitle(exercise.map { e in
      e.targetSets.map { "Set \(min(e.sets.count + 1, $0)) of \($0)" } ?? "Set \(e.sets.count + 1)"
    } ?? "")
    .onAppear {
      focus = .weight
      guard let exercise else { return }
      let index = exercise.sets.count
      let previous = exercise.sets.last.map { (weight: $0.weight, reps: $0.reps) }
        ?? (exercise.last.indices.contains(index) ? exercise.last[index] : exercise.last.first)
          .map { (weight: $0.weight, reps: $0.reps) }
      if let previous {
        weight = previous.weight
        reps = Double(previous.reps)
      }
    }
  }

  /// Tap one to give it the crown; the ring shows which.
  private func box(_ title: String, _ value: String, _ unit: String, selected: Bool) -> some View {
    VStack(spacing: 0) {
      Text(title).font(.caption2.weight(.semibold)).foregroundStyle(WatchPalette.secondary)
      Text(value).font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1).minimumScaleFactor(0.6)
      Text(unit).font(.caption2).foregroundStyle(WatchPalette.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
    .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? fitness : .clear, lineWidth: 2))
  }
}

private struct AddExerciseView: View {
  @EnvironmentObject private var workout: WorkoutSession
  let onDone: () -> Void
  @State private var name = ""

  var body: some View {
    VStack(spacing: 8) {
      TextField("Exercise name", text: $name)
        .onSubmit {
          workout.addExercise(name)
          onDone()
        }
      Text("Dictate or scribble its name.").font(.caption2).foregroundStyle(WatchPalette.secondary)
    }
    .scenePadding(.horizontal)
    .navigationTitle("Add exercise")
  }
}

private struct RestView: View {
  @EnvironmentObject private var workout: WorkoutSession

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let left = max(0, (workout.restEnds ?? context.date).timeIntervalSince(context.date))
      VStack(spacing: 6) {
        ZStack {
          Circle().stroke(WatchPalette.capacity.opacity(0.25), lineWidth: 7)
          Circle()
            .trim(from: 0, to: left / Double(max(1, workout.restLength)))
            .stroke(WatchPalette.capacity, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(-90))
          VStack(spacing: 0) {
            Text(clock(left.rounded(.up))).font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
            Text("of \(clock(TimeInterval(workout.restLength)))")
              .font(.caption2).foregroundStyle(WatchPalette.secondary)
            if let bpm = workout.bpm {
              Text("\(bpm) bpm").font(.caption2).foregroundStyle(WatchPalette.secondary)
            }
          }
        }
        .frame(width: 92, height: 92)
        if workout.exercises.indices.contains(workout.current) {
          let next = workout.exercises[workout.current]
          Text("Next · \(next.name), set \(next.sets.count + 1)")
            .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        HStack(spacing: 6) {
          Button("+15 s") { workout.addRest(15) }
          Button("Skip") { workout.stopRest() }
        }
        .font(.footnote.weight(.semibold))
      }
      .scenePadding(.horizontal)
    }
  }
}

private struct WorkoutControlsView: View {
  @EnvironmentObject private var workout: WorkoutSession
  let onAdd: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Header(color: workout.kind.isCardio ? WatchPalette.demand : fitness)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
          control("End", icon: "xmark", color: WatchPalette.stress) { workout.end() }
          control(workout.paused ? "Resume" : "Pause", icon: workout.paused ? "arrow.clockwise" : "pause.fill",
                  color: calorie) { workout.togglePause() }
          if !workout.kind.isCardio {
            if workout.current < workout.exercises.count - 1 {
              control("Next exercise", icon: "arrow.right", color: fitness) { workout.nextExercise() }
            }
            control("Add exercise", icon: "plus", color: .white, action: onAdd)
          }
        }
      }
      .scenePadding(.horizontal)
    }
  }

  private func control(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: icon)
          .font(.title3.weight(.bold))
          .foregroundStyle(color)
          .frame(width: 46, height: 46)
          .background(color.opacity(0.22), in: Circle())
        Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: Summary

private struct WorkoutSummaryView: View {
  @EnvironmentObject private var workout: WorkoutSession
  let summary: WorkoutSession.Summary

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(summary.name).font(.footnote.weight(.semibold))
            .foregroundStyle(summary.kind.isCardio ? WatchPalette.demand : fitness).lineLimit(1)
          Spacer(minLength: 4)
          if summary.seconds >= 30 {
            Label("Saved", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(fitness)
          }
        }
        HStack(alignment: .firstTextBaseline) {
          Text(clock(TimeInterval(summary.seconds)))
            .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
          Spacer(minLength: 4)
          Text("\(summary.calories) cal").font(.footnote.weight(.semibold)).foregroundStyle(calorie)
        }
        HStack(spacing: 4) {
          tile(summary.averageHeartRate.map(String.init) ?? "–", "Avg bpm")
          tile(summary.maxHeartRate.map(String.init) ?? "–", "Max bpm")
          if summary.kind.isCardio {
            tile(String(format: "%.2f", summary.km), "km")
          } else {
            tile("\(summary.sets)", summary.sets == 1 ? "Set" : "Sets")
          }
        }
        if let most = summary.zoneSeconds.indices.max(by: { summary.zoneSeconds[$0] < summary.zoneSeconds[$1] }),
           summary.zoneSeconds[most] >= 60 {
          zoneBar
          Text("Most time in Zone \(most + 1) · \(Int(summary.zoneSeconds[most] / 60)) min")
            .font(.caption2).foregroundStyle(WatchPalette.secondary)
        }
        Text(footer).font(.caption2).foregroundStyle(WatchPalette.secondary)
        Button("Done") { workout.close() }.font(.footnote.weight(.semibold))
      }
      .scenePadding(.horizontal)
    }
  }

  private var footer: String {
    if summary.seconds < 30 { return "Too short to save." }
    let health = workout.savedToHealth == true ? "Saved to Health. "
      : workout.savedToHealth == nil ? "Saving to Health… " : ""
    return health + "Your iPhone adds it to your workouts and today's Effort."
  }

  private var zoneBar: some View {
    let total = max(1, summary.zoneSeconds.reduce(0, +))
    return GeometryReader { geometry in
      HStack(spacing: 2) {
        ForEach(0..<5, id: \.self) { zone in
          if summary.zoneSeconds[zone] > 0 {
            Rectangle().fill(zoneColors[zone])
              .frame(width: max(2, (geometry.size.width - 8) * summary.zoneSeconds[zone] / total))
          }
        }
      }
    }
    .frame(height: 7)
    .clipShape(Capsule())
    .accessibilityLabel("Time in each heart rate zone")
  }

  private func tile(_ value: String, _ label: String) -> some View {
    VStack(spacing: 0) {
      Text(value).font(.system(.headline, design: .rounded).weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
      Text(label).font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .background(WatchPalette.tile, in: RoundedRectangle(cornerRadius: 12))
  }
}

// MARK: Formatting

private func clock(_ seconds: TimeInterval) -> String {
  let s = Int(seconds)
  return s >= 3600
    ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    : String(format: "%d:%02d", s / 60, s % 60)
}

private func pounds(_ weight: Double) -> String {
  weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
}
