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
                    expandedSummary(context)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    bpmGauge(context)
                }
            } compactLeading: {
                compactTimer(context)
            } compactTrailing: {
                compactBPM(context)
            } minimal: {
                minimalTimer(context)
            }
            .keylineTint(.red)
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exerciseName(context))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)

                Text(seriesText(context))
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)

                HStack(spacing: 4) {
                    Image(systemName: "stopwatch.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    timerText(context, font: .caption.bold())
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                BPMDial(bpm: context.state.currentBPM)
                    .frame(width: 72, height: 72)

                Text("BPM")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func expandedSummary(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(exerciseName(context))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(seriesText(context))
                .font(.caption.bold())
                .foregroundStyle(.green)

            HStack(spacing: 4) {
                Image(systemName: "stopwatch.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)

                timerText(context, font: .caption2.bold())
            }
        }
    }

    private func bpmGauge(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(spacing: 3) {
            BPMDial(bpm: context.state.currentBPM)
                .frame(width: 58, height: 58)

            Text("BPM")
                .font(.caption2.bold())
                .tracking(1.2)
                .foregroundStyle(.red)
        }
    }

    private func compactTimer(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "stopwatch.fill")
                .foregroundStyle(.orange)

            timerText(context, font: .caption2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func compactBPM(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)

            Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM) BPM" : "-- BPM")
                .font(.caption2.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func minimalTimer(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "stopwatch.fill")
                .foregroundStyle(.orange)

            timerText(context, font: .caption2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    @ViewBuilder
    private func timerText(
        _ context: ActivityViewContext<WorkoutActivityAttributes>,
        font: Font
    ) -> some View {
        if let endDate = context.state.timerEndDate, context.state.isRestTimerActive {
            Text(endDate, style: .timer)
                .font(font)
                .monospacedDigit()
                .foregroundColor(.orange)
        } else {
            Text("00:00")
                .font(font)
                .monospacedDigit()
                .foregroundColor(.orange)
        }
    }

    private func exerciseName(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
        let name = context.state.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? context.attributes.workoutName : name
    }

    private func seriesText(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> String {
        guard context.state.totalSets > 0 else { return "Sin series" }
        return "Serie \(context.state.currentSet) de \(context.state.totalSets)"
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
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(3)
    }
}
