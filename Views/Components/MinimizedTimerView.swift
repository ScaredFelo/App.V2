import SwiftUI

public struct MinimizedTimerView: View {
    public let timeRemaining: Int
    public let totalSeconds: Int
    public let isPaused: Bool
    public let onExpand: () -> Void
    public let onTogglePause: () -> Void
    public let onAdd10: () -> Void
    public let onSub10: () -> Void
    public let onSkip: () -> Void

    public init(
        timeRemaining: Int,
        totalSeconds: Int,
        isPaused: Bool,
        onExpand: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onAdd10: @escaping () -> Void,
        onSub10: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.timeRemaining = timeRemaining
        self.totalSeconds = totalSeconds
        self.isPaused = isPaused
        self.onExpand = onExpand
        self.onTogglePause = onTogglePause
        self.onAdd10 = onAdd10
        self.onSub10 = onSub10
        self.onSkip = onSkip
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(timeFormatted(timeRemaining))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize()
                .allowsHitTesting(false)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                timerButton(
                    icon: isPaused ? "play.fill" : "pause.fill",
                    action: onTogglePause,
                    accessibilityLabel: isPaused ? "Reanudar" : "Pausar"
                )

                timerButton(
                    icon: "gobackward.10",
                    action: onSub10,
                    accessibilityLabel: "Restar 10 segundos"
                )

                timerButton(
                    icon: "goforward.10",
                    action: onAdd10,
                    accessibilityLabel: "Añadir 10 segundos"
                )

                timerButton(
                    icon: "forward.end.fill",
                    tint: .white.opacity(0.95),
                    action: onSkip,
                    accessibilityLabel: "Omitir descanso"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Button(action: onExpand) {
                Color.clear
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expandir temporizador")
        }
        .background(Color.black.opacity(0.8), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(alignment: .bottom) {
            progressBar
        }
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                Capsule()
                    .fill(progressTint)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 22)
        .padding(.bottom, 7)
        .animation(.linear(duration: 0.25), value: progress)
        .allowsHitTesting(false)
    }

    private func timerButton(
        icon: String,
        tint: Color = .white.opacity(0.85),
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .renderingMode(.template)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let elapsed = Double(max(0, totalSeconds - timeRemaining))
        return min(max(elapsed / Double(totalSeconds), 0), 1)
    }

    private var progressTint: Color {
        isPaused ? Color.orange.opacity(0.85) : Color.white.opacity(0.8)
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
