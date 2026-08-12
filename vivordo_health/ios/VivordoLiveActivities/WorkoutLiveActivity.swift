import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
  private let purple = Color(red: 0.42, green: 0.36, blue: 0.91)

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      lockScreenView(context)
        .activityBackgroundTint(Color.black.opacity(0.88))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "com.vivordo.health://fitness"))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          workoutIcon(size: 38)
        }
        DynamicIslandExpandedRegion(.trailing) {
          elapsedTimer(startedAt: context.attributes.startedAt, font: .title3)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text("Workout in progress")
              .foregroundStyle(.secondary)
            Spacer()
            Text(exerciseLabel(context.state.exerciseCount))
              .foregroundStyle(purple)
          }
          .font(.caption)
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill")
          .foregroundStyle(purple)
      } compactTrailing: {
        elapsedTimer(startedAt: context.attributes.startedAt, font: .caption2)
          .frame(maxWidth: 48)
      } minimal: {
        Image(systemName: "dumbbell.fill")
          .foregroundStyle(purple)
      }
      .widgetURL(URL(string: "com.vivordo.health://fitness"))
      .keylineTint(purple)
    }
  }

  private func lockScreenView(
    _ context: ActivityViewContext<WorkoutActivityAttributes>
  ) -> some View {
    HStack(spacing: 14) {
      workoutIcon(size: 48)

      VStack(alignment: .leading, spacing: 4) {
        Text(context.state.title)
          .font(.headline)
          .lineLimit(1)
        Text(context.state.status)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 10)

      VStack(alignment: .trailing, spacing: 4) {
        elapsedTimer(startedAt: context.attributes.startedAt, font: .title3)
        Text(exerciseLabel(context.state.exerciseCount))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.white)
    .padding(16)
  }

  private func workoutIcon(size: CGFloat) -> some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [purple.opacity(0.72), purple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Image(systemName: "dumbbell.fill")
        .foregroundStyle(.white)
        .font(.system(size: size * 0.4, weight: .semibold))
    }
    .frame(width: size, height: size)
  }

  private func elapsedTimer(startedAt: Date, font: Font) -> some View {
    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
        .font(font.weight(.semibold))
        .monospacedDigit()
      .lineLimit(1)
  }

  private func exerciseLabel(_ count: Int) -> String {
    count == 1 ? "1 exercise" : "\(count) exercises"
  }
}
