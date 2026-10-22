import SwiftUI

public struct MinimizedTimerView: View {
    public let timeRemaining: Int
    public let onExpand: () -> Void
    public let onAdd10: () -> Void
    public let onSkip: () -> Void

    public var body: some View {
        HStack(spacing: 16) {
            Button(action: onExpand) {
                Image(systemName: "chevron.up")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Descanso")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(timeFormatted(timeRemaining))
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(.white)
            }

            Spacer()

            Button(action: onAdd10) {
                Text("+10s")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            Button(action: onSkip) {
                Text("Omitir")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.9))
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private func timeFormatted(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
