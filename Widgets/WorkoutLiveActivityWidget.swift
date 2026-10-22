import SwiftUI
import WidgetKit
import ActivityKit

@main
struct AppGymWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Vista en Pantalla de Bloqueo
            HStack {
                VStack(alignment: .leading) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(context.state.timerEndDate, style: .timer)
                    .font(.title2)
                    .bold()
                    .foregroundStyle(.green)
            }
            .padding()
            .activityBackgroundTint(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.exerciseName)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.white)
                        Text("\(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--") BPM")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.timerEndDate, style: .timer)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.green)
                        .monospacedDigit()
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text("\(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--")")
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                Text(context.state.timerEndDate, style: .timer)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.green)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }
}
