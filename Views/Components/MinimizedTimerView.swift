import SwiftUI

public struct MinimizedTimerView: View {
    public let timeRemaining: Int
    public let isPaused: Bool
    public let onExpand: () -> Void
    public let onTogglePause: () -> Void
    public let onAdd10: () -> Void
    public let onSub10: () -> Void
    public let onSkip: () -> Void

    public init(
        timeRemaining: Int,
        isPaused: Bool,
        onExpand: @escaping () -> Void,
        onTogglePause: @escaping () -> Void,
        onAdd10: @escaping () -> Void,
        onSub10: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.timeRemaining = timeRemaining
        self.isPaused = isPaused
        self.onExpand = onExpand
        self.onTogglePause = onTogglePause
        self.onAdd10 = onAdd10
        self.onSub10 = onSub10
        self.onSkip = onSkip
    }

    public var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                Image(systemName: "chevron.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 36)
                    .fixedSize()
            }
            .accessibilityLabel("Expandir temporizador")

            VStack(alignment: .leading, spacing: 1) {
                Text(isPaused ? "Pausado" : "Descanso")
                    .font(.caption2)
                    .foregroundStyle(isPaused ? Color.orange : Color.secondary)
                Text(timeFormatted(timeRemaining))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .fixedSize()

            Spacer(minLength: 4)

            timerButton(
                icon: isPaused ? "play.fill" : "pause.fill",
                tint: .white,
                background: Color(.systemGray6).opacity(0.3),
                action: onTogglePause,
                accessibilityLabel: isPaused ? "Reanudar" : "Pausar"
            )

            timerButton(
                icon: "goback.10",
                tint: .white,
                background: Color(.systemGray6).opacity(0.3),
                action: onSub10,
                accessibilityLabel: "Restar 10 segundos"
            )

            timerButton(
                icon: "goforward.10",
                tint: .white,
                background: Color(.systemGray6).opacity(0.3),
                action: onAdd10,
                accessibilityLabel: "Añadir 10 segundos"
            )

            timerButton(
                icon: "forward.end.fill",
                tint: .black,
                background: .white,
                action: onSkip,
                accessibilityLabel: "Omitir descanso"
            )
        }
        .frame(height: 36)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 56)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func timerButton(
        icon: String,
        tint: Color,
        background: Color,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(background)
                .clipShape(Circle())
                .fixedSize()
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
