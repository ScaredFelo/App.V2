import Foundation
import SwiftUI

public struct CircularTimerView: View {
    public let timeRemaining: Int
    public let totalSeconds: Int
    public let isPaused: Bool
    public let onAdd10: () -> Void
    public let onSub10: () -> Void
    public let onTogglePause: () -> Void
    public let onSkip: () -> Void
    public let onMinimize: () -> Void

    @ObservedObject private var bpmManager = BPMManager.shared

    private let dialSize: CGFloat = 260
    private let outerLineWidth: CGFloat = 14
    private let arcStartAngle: Double = 135
    private let arcSpan: Double = 270
    private let bpmRange: ClosedRange<Double> = 50...220
    private let bpmMarks = [50, 70, 90, 110, 130, 150, 220]

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max(Double(timeRemaining) / Double(totalSeconds), 0), 1)
    }

    private var effectiveBPM: Int {
        bpmManager.currentBPM > 0 ? min(max(bpmManager.currentBPM, 50), 220) : 50
    }

    private var needleAngle: Double {
        tachometerAngle(for: effectiveBPM) - 270
    }

    private var zoneColor: Color {
        guard bpmManager.currentBPM > 0 else { return .green }
        switch bpmManager.currentBPM {
        case ..<90:
            return .green
        case ..<150:
            return .orange
        default:
            return .red
        }
    }

    public init(
        timeRemaining: Int,
        totalSeconds: Int,
        isPaused: Bool,
        onAdd10: @escaping () -> Void,
        onSub10: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onMinimize: @escaping () -> Void
    ) {
        self.timeRemaining = timeRemaining
        self.totalSeconds = totalSeconds
        self.isPaused = isPaused
        self.onAdd10 = onAdd10
        self.onSub10 = onSub10
        self.onTogglePause = onTogglePause
        self.onSkip = onSkip
        self.onMinimize = onMinimize
    }

    public var body: some View {
        VStack(spacing: 20) {
            dial

            HStack(spacing: 20) {
                Button(action: onSub10) {
                    Image(systemName: "gobackward.10")
                        .renderingMode(.template)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 40)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(20)
                        .fixedSize()
                }

                Button(action: onTogglePause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isPaused ? .black : .white)
                        .frame(width: 60, height: 40)
                        .background(isPaused ? Color.white : Color(.systemGray6).opacity(0.3))
                        .cornerRadius(20)
                        .fixedSize()
                }
                .accessibilityLabel(isPaused ? "Reanudar descanso" : "Pausar descanso")

                Button(action: onAdd10) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 40)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(20)
                        .fixedSize()
                }
            }

            Button(action: onSkip) {
                Text("Omitir Descanso")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            }
        }
        .padding(24)
        .overlay(alignment: .topTrailing) {
            Button(action: onMinimize) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityLabel("Minimizar temporizador")
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var dial: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(arcStartAngle))

            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(
                    Color.green,
                    style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(arcStartAngle))
                .shadow(color: Color.green.opacity(0.35), radius: 6)
                .animation(.linear(duration: 1), value: progress)

            Circle()
                .inset(by: 28)
                .trim(from: 0, to: 0.75)
                .stroke(
                    zoneColor.opacity(0.45),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(arcStartAngle))
                .animation(.easeInOut(duration: 0.4), value: zoneColor)

            ForEach(bpmMarks, id: \.self) { bpm in
                tickMark(for: bpm)
            }

            needle

            readout
        }
        .frame(width: dialSize, height: dialSize)
    }

    private var needle: some View {
        ZStack {
            Capsule()
                .fill(zoneColor)
                .frame(width: 3, height: 92)
                .offset(y: -46)
                .shadow(color: zoneColor.opacity(0.5), radius: 6)

            Circle()
                .fill(zoneColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.6), lineWidth: 2)
                )
        }
        .frame(width: dialSize, height: dialSize)
        .rotationEffect(.degrees(needleAngle))
        .opacity(0.85)
        .animation(.easeOut(duration: 0.45), value: needleAngle)
    }

    private var readout: some View {
        VStack(spacing: 2) {
            Text(isPaused ? "PAUSADO" : "DESCANSO")
                .font(.caption2.bold())
                .tracking(1.5)
                .foregroundStyle(isPaused ? Color.orange : Color.secondary)

            Text(timeFormatted(timeRemaining))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(bpmManager.currentBPM > 0 ? "\(bpmManager.currentBPM) BPM" : "-- BPM")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(zoneColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func tickMark(for bpm: Int) -> some View {
        let angle = tachometerAngle(for: bpm)
        let radians = angle * .pi / 180
        let center = dialSize / 2
        let isBoundary = bpm == 50 || bpm == 220

        return ZStack {
            Capsule()
                .fill(zoneColor.opacity(0.85))
                .frame(width: 1.5, height: isBoundary ? 12 : 8)
                .rotationEffect(.degrees(angle + 90))
                .position(
                    x: center + CGFloat(cos(radians)) * 94,
                    y: center + CGFloat(sin(radians)) * 94
                )

            Text("\(bpm)")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(zoneColor.opacity(0.65))
                .position(
                    x: center + CGFloat(cos(radians)) * 78,
                    y: center + CGFloat(sin(radians)) * 78
                )
        }
    }

    private func tachometerAngle(for bpm: Int) -> Double {
        let clamped = min(max(Double(bpm), bpmRange.lowerBound), bpmRange.upperBound)
        let fraction = (clamped - bpmRange.lowerBound) / (bpmRange.upperBound - bpmRange.lowerBound)
        return arcStartAngle + fraction * arcSpan
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
