import SwiftUI
import WidgetKit
import ActivityKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded View
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("\(context.state.currentBPM) BPM")
                            .font(.subheadline.bold())
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        if context.state.isBpmMode {
                            Text("Recuperación activa")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Objetivo: < \(context.state.targetBPM) BPM")
                                .font(.title3.bold())
                                .foregroundStyle(context.state.currentBPM <= context.state.targetBPM ? .green : .red)
                        } else {
                            Text("Descanso")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(timeFormatted(context.state.remainingSeconds))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                    Text(context.state.exerciseName)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
            } compactTrailing: {
                if context.state.isBpmMode {
                    Text("\(context.state.currentBPM)")
                        .font(.caption.bold())
                        .foregroundStyle(context.state.currentBPM <= context.state.targetBPM ? .green : .red)
                } else {
                    Text(timeFormatted(context.state.remainingSeconds))
                        .font(.caption.bold())
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.white)
            }
        }
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.routineName, systemImage: "figure.strengthtraining.traditional")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(context.state.exerciseName)
                    .font(.caption)
                    .foregroundStyle(.white)
            }

            HStack {
                if context.state.isBpmMode {
                    VStack(alignment: .leading) {
                        Text("Pulso Objetivo: < \(context.state.targetBPM) BPM")
                            .font(.subheadline.bold())
                        Text("Actual: \(context.state.currentBPM) BPM")
                            .font(.caption)
                            .foregroundStyle(context.state.currentBPM <= context.state.targetBPM ? .green : .red)
                    }
                } else {
                    VStack(alignment: .leading) {
                        Text("Descanso Restante")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timeFormatted(context.state.remainingSeconds))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    Text("\(context.state.currentBPM)")
                        .font(.title3.bold())
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.8))
        .cornerRadius(16)
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
