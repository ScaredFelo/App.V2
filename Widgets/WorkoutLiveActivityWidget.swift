import SwiftUI
import WidgetKit
import ActivityKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Vista en Pantalla de Bloqueo / Notificaciones
            HStack {
                VStack(alignment: .leading) {
                    Text(context.attributes.workoutName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.exerciseName)
                        .font(.headline)
                    Text("Serie \(context.state.currentSet)")
                        .font(.subheadline)
                }
                Spacer()
                Text(context.state.timerEndDate, style: .timer)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text(context.state.exerciseName)
                            .font(.caption)
                            .bold()
                        Text("Serie \(context.state.currentSet)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.timerEndDate, style: .timer)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            }
        }
    }
}
