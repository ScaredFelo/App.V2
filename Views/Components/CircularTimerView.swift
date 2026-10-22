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

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(max(0, timeRemaining)) / Double(totalSeconds)
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
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color(.systemGray6), lineWidth: 12)
                
                // Progress Arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(isPaused ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: progress)

                // Time Display
                VStack(spacing: 4) {
                    Text(isPaused ? "PAUSADO" : "DESCANSO")
                        .font(.caption2.bold())
                        .foregroundStyle(isPaused ? Color.orange : Color.secondary)
                    Text(timeFormatted(timeRemaining))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            .frame(width: 180, height: 180)

            // Adjust Controls (+10s / -10s)
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

            // Skip Button
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
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding()
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
