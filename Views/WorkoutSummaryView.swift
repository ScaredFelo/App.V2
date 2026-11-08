import SwiftUI
import SwiftData

/// Pantalla de resumen de sesión mostrada al completar todas las series del modo Big Picture.
/// Muestra tiempo total, volumen total y pulsaciones medias, con un botón para terminar la sesión.
public struct WorkoutSummaryView: View {
    @ObservedObject private var viewModel: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    let modelContext: ModelContext
    var onFinish: (() -> Void)?

    public init(viewModel: ActiveWorkoutViewModel, modelContext: ModelContext, onFinish: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.modelContext = modelContext
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // Encabezado
                VStack(spacing: 8) {
                    Text("Entrenamiento completado")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(viewModel.routine.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                Spacer(minLength: 0)

                // Métricas del resumen
                VStack(spacing: 20) {
                    summaryRow(
                        icon: "clock.fill",
                        title: "Tiempo total",
                        value: viewModel.totalWorkoutDurationFormatted
                    )

                    summaryRow(
                        icon: "dot.circle.fill",
                        title: "Volumen total",
                        value: "\(String(format: "%.0f", viewModel.session.totalVolumeKg)) kg"
                    )

                    summaryRow(
                        icon: "heart.fill",
                        title: "Pulsaciones medias",
                        value: "\(viewModel.averageBPM) BPM"
                    )
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 0)

                // Botón inferior destacado: Terminar sesión
                Button {
                    viewModel.finishWorkout(modelContext: modelContext)
                    onFinish?()
                } label: {
                    Text("Terminar sesión")
                        .font(.headline.bold())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    private func summaryRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(12)
    }
}
