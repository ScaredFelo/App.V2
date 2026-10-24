import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct AppGymWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(Color(red: 0.04, green: 0.04, blue: 0.05))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.workoutName.uppercased())
                            .font(.caption2.bold())
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(context.state.isPaused ? "PAUSADO" : "EN CURSO")
                            .font(.caption2.bold())
                            .foregroundStyle(context.state.isPaused ? Color.orange : Color.green)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    timerText(context)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    BPMDial(bpm: context.state.currentBPM)
                        .frame(width: 58, height: 58)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isPaused ? "pause.circle.fill" : "bolt.fill")
                            .foregroundStyle(context.state.isPaused ? Color.orange : Color.green)

                        Text(context.state.isPaused ? "Entrenamiento pausado" : "Entrenamiento activo")
                            .font(.caption2.bold())
                            .foregroundStyle(context.state.isPaused ? Color.orange : Color.green)

                        Spacer(minLength: 8)

                        Text("AppGym")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)

                    timerText(context)
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            } compactTrailing: {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)

                    Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM) BPM" : "-- BPM")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            } minimal: {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)

                    Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--")
                        .font(.caption2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            .keylineTint(.red)
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(.green)

                    Text(context.attributes.workoutName.uppercased())
                        .font(.caption2.bold())
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    timerText(context)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(context.state.isPaused ? "PAUSA" : "EN CURSO")
                        .font(.caption2.bold())
                        .foregroundStyle(context.state.isPaused ? Color.orange : Color.green)
                }

                Label(context.state.isPaused ? "Entrenamiento pausado" : "Entrenamiento en directo", systemImage: "waveform.path.ecg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                BPMDial(bpm: context.state.currentBPM)
                    .frame(width: 66, height: 66)

                Text("BPM")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func timerText(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        Text(Date().addingTimeInterval(-context.state.elapsedTime), style: .timer)
    }
}

private struct BPMDial: View {
    let bpm: Int

    private var fraction: CGFloat {
        let clamped = min(max(Double(bpm), 50), 210)
        return CGFloat((clamped - 50) / 160)
    }

    private var gaugeColor: Color {
        switch bpm {
        case ..<90:
            return .green
        case ..<150:
            return .orange
        default:
            return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)

            Circle()
                .trim(from: 0, to: bpm > 0 ? fraction : 0)
                .stroke(
                    gaugeColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)

                Text(bpm > 0 ? "\(bpm)" : "--")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(3)
    }
}
