import SwiftUI
import SwiftData
import Charts

/// Vista dedicada al modo Big Picture (entrenamiento con interfaz simplificada y
/// controles de gran tamaño). Extraída de `ActiveWorkoutView` para mantener la
/// separación de responsabilidades y el cuerpo de esa vista enfocado al modo normal.
public struct BigPictureWorkoutView: View {
    @ObservedObject private var viewModel: ActiveWorkoutViewModel
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @Environment(\.dismiss) private var dismiss

    let modelContext: ModelContext

    /// Callback invocado cuando el entrenamiento finaliza automáticamente
    /// (última serie del último ejercicio). El contenedor lo usa para hacer `dismiss()`.
    var onWorkoutFinished: (() -> Void)?

    @State private var weightInput = ""
    @FocusState private var isWeightFieldFocused: Bool

    public init(viewModel: ActiveWorkoutViewModel, modelContext: ModelContext, onWorkoutFinished: (() -> Void)? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.modelContext = modelContext
        self.onWorkoutFinished = onWorkoutFinished
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Barra superior: cancelar + nombre rutina
                    bigPictureTopBar

                    // MARK: - Header BPM
                    headerBPMView

                    // MARK: - Ejercicio actual, rango objetivo y siguiente
                    exerciseTitleView

                    // MARK: - Peso y repeticiones
                    BigPictureControlsView(
                        weightInput: $weightInput,
                        currentWeight: viewModel.bigPictureCurrentWeight,
                        currentReps: viewModel.bigPictureCurrentReps,
                        modelContext: modelContext,
                        onWeightChange: { value in
                            viewModel.bigPictureUpdateWeight(value, modelContext: modelContext)
                        },
                        onRepsChange: { delta in
                            viewModel.bigPictureAdjustReps(delta)
                        }
                    )

                    // MARK: - Temporizador integrado o botón registrar serie
                    restTimerProgressView

                    // MARK: - Gráfica BPM (visible durante todo el entrenamiento)
                    BPMChartView(samples: viewModel.bpmHistoryLast3Minutes)

                    // MARK: - Parrilla de series (historial vs nueva marca)
                    BigPictureSetsGridView(
                        currentExercise: viewModel.bigPictureCurrentExercise,
                        rows: viewModel.bigPictureSetRows(modelContext: modelContext)
                    )

                    // MARK: - Notas del ejercicio actual
                    exerciseNotesSection

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Cabecera y barra superior

    /// Relleno superior (cerrar + nombre de rutina).
    @ViewBuilder
    private var bigPictureTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)
            .padding(.leading, 6)

            Spacer()

            Text(viewModel.routine.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
    }

    /// Encabezado de pulsaciones (BPM).
    @ViewBuilder
    private var headerBPMView: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("\(Int(healthKitManager.currentBPM)) BPM")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                    .contentTransition(.numericText())
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 24)
    }

    /// Título del ejercicio, rango objetivo en verde y siguiente ejercicio.
    @ViewBuilder
    private var exerciseTitleView: some View {
        VStack(spacing: 4) {
            Text(viewModel.bigPictureCurrentExercise)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let routineExercise = viewModel.bigPictureCurrentRoutineExercise {
                Text("\(routineExercise.targetRepsMin) - \(routineExercise.targetRepsMax) reps")
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if !viewModel.bigPictureNextExercise.isEmpty {
                Text(viewModel.bigPictureNextExercise)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Temporizador

    /// Barra de descanso con temporizador centrado y botones de pausa/saltar,
    /// o botón "Registrar serie" cuando no hay descanso activo.
    @ViewBuilder
    private var restTimerProgressView: some View {
        if viewModel.bigPictureIsTimerShowing {
            bigPictureTimerBar
            bigPictureTimerControls
        } else {
            Button {
                viewModel.bigPictureRegisterSet(modelContext: modelContext)
            } label: {
                Text("REGISTRAR SERIE")
                    .font(.title2.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        }
    }

    private var bigPictureTimerBar: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            GeometryReader { geometry in
                let barWidth: CGFloat = geometry.size.width
                let progress: CGFloat = CGFloat(viewModel.bigPictureRestProgress)
                let filledWidth: CGFloat = max(0, barWidth * progress)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: barWidth, height: 36)

                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .frame(
                            width: filledWidth,
                            height: 36
                        )
                        .animation(.linear(duration: 1.0), value: viewModel.bigPictureRestProgress)

                    Text(viewModel.bigPictureRemainingTimeFormatted)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .blendMode(.difference)
                        .frame(width: barWidth, alignment: .center)
                }
                .frame(width: barWidth, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 36)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
        }
    }

    private var bigPictureTimerControls: some View {
        HStack(spacing: 14) {
            Button {
                if viewModel.isRestPaused {
                    viewModel.resumeRest()
                } else {
                    viewModel.pauseRest()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isRestPaused ? "play.fill" : "pause.fill")
                    Text(viewModel.isRestPaused ? "Reanudar" : "Pausar")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
                .cornerRadius(10)
            }

            Button {
                viewModel.skipRest()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.end.fill")
                    Text("Saltar")
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    // MARK: - Notas del ejercicio

    /// Campo editable de notas vinculado al ejercicio actual en tiempo real.
    @ViewBuilder
    private var exerciseNotesSection: some View {
        if let routineExercise = viewModel.bigPictureCurrentRoutineExercise {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notas del ejercicio")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                TextEditor(text: notesBinding(for: routineExercise))
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(minHeight: 80, alignment: .topLeading)
                    .padding(8)
                    .background(Color(.systemGray6).opacity(0.2))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 24)
        }
    }

    private func notesBinding(for routineExercise: RoutineExercise) -> Binding<String> {
        Binding(
            get: { routineExercise.notes },
            set: {
                routineExercise.notes = $0
                try? modelContext.save()
            }
        )
    }

    // MARK: - Helpers

    private func formattedWeight(_ weight: Double) -> String {
        guard weight > 0 else { return "" }
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Big Picture Controls View (peso + repeticiones)

struct BigPictureControlsView: View {
    @Binding var weightInput: String
    @FocusState private var isWeightFocused: Bool
    var currentWeight: Double
    var currentReps: Int
    var modelContext: ModelContext
    var onWeightChange: (Double) -> Void
    var onRepsChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Peso central con teclado numérico directo
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $weightInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($isWeightFocused)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 100, alignment: .trailing)
                    .onChange(of: weightInput) { _, newValue in
                        guard isWeightFocused else { return }
                        let normalized = newValue.replacingOccurrences(of: ",", with: ".")
                        guard let value = Double(normalized) else { return }
                        onWeightChange(value)
                    }
                    .onSubmit { isWeightFocused = false }
                    .accessibilityLabel("Peso actual. Toca para editar.")

                Text("kg")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .onChange(of: currentWeight) { _, newWeight in
                guard !isWeightFocused else { return }
                weightInput = formattedWeight(newWeight)
            }

            // MARK: - Repeticiones (centrado y compacto)
            HStack(spacing: 16) {
                Button {
                    onRepsChange(-1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }

                VStack(spacing: 2) {
                    Text("\(currentReps)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("REPS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                Button {
                    onRepsChange(1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func formattedWeight(_ weight: Double) -> String {
        guard weight > 0 else { return "" }
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - BPM Chart View (ventana de 3 minutos)

struct BPMChartView: View {
    let samples: [ActiveWorkoutViewModel.BPMDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PULSACIONES · ÚLTIMOS 3 MIN")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                if samples.isEmpty {
                    Text("Esperando datos de frecuencia cardíaca...")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                } else {
                    Chart(samples) { (sample: ActiveWorkoutViewModel.BPMDataPoint) in
                        LineMark(
                            x: .value("Tiempo", sample.timestamp),
                            y: .value("BPM", Double(sample.bpm))
                        )
                        .foregroundStyle(Color.red)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Tiempo", sample.timestamp),
                            y: .value("BPM", Double(sample.bpm))
                        )
                        .foregroundStyle(Color.red)
                    }
                    .chartXScale(domain: timeline.date.addingTimeInterval(-180)...timeline.date)
                    .chartYScale(domain: 40...200)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
    }
}

// MARK: - Big Picture Sets Grid View (3 columnas)

struct BigPictureSetsGridView: View {
    var currentExercise: String
    var rows: [ActiveWorkoutViewModel.BigPictureSetRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Última sesión")
                .font(.headline.bold())
                .foregroundStyle(.white)

            if rows.isEmpty {
                Text("Sin series registradas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let columns: [GridItem] = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    Text("Serie")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text("Última Sesión")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text("Nueva Marca")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    ForEach(rows) { row in
                        BigPictureSetRowView(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

struct BigPictureSetRowView: View {
    var row: ActiveWorkoutViewModel.BigPictureSetRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Serie \(row.setNumber)")
                .font(.caption2.bold())
                .foregroundStyle(.white)

            if let previous: String = row.previousText {
                Text(previous)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("-")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            if let current: String = row.currentText {
                Text(current)
                    .font(.caption2.bold())
                    .foregroundColor(.green)
            } else {
                Text("-")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
    }
}
