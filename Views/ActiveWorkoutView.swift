import SwiftUI
import SwiftData

public struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ActiveWorkoutViewModel
    @State private var showingFinishConfirmation = false
    @ObservedObject private var bpmManager = BPMManager.shared

    public init(session: WorkoutSession, routine: Routine, modelContext: ModelContext) {
        _viewModel = State(initialValue: ActiveWorkoutViewModel(session: session, routine: routine, modelContext: modelContext))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // List of exercises on the main level
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Header Status & BPM
                    workoutHeader
                        .padding(.top, 10)
                    
                    ForEach(viewModel.routine.exercises.sorted(by: { $0.sortOrder < $1.sortOrder })) { routineExercise in
                        if let exercise = routineExercise.exercise {
                            ExerciseCardView(
                                routineExercise: routineExercise,
                                exercise: exercise,
                                sets: viewModel.activeSets[routineExercise.id] ?? [],
                                onToggleSet: { setIndex in
                                    viewModel.toggleSetCompletion(for: routineExercise.id, setIndex: setIndex, modelContext: modelContext)
                                },
                                onUpdateSet: { setIndex, weight, reps in
                                    if var sets = viewModel.activeSets[routineExercise.id], sets.indices.contains(setIndex) {
                                        sets[setIndex].weight = weight
                                        sets[setIndex].reps = reps
                                        viewModel.activeSets[routineExercise.id] = sets
                                    }
                                }
                            )
                        }
                    }

                    // Finish Workout Button
                    Button(action: {
                        showingFinishConfirmation = true
                    }) {
                        Text("Finalizar Entrenamiento")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }

            // Floating Rest UI
            if viewModel.isResting {
                if !viewModel.isTimerMinimized {
                    // Eliminado Color.black.opacity(0.85).ignoresSafeArea()
                    CircularTimerView(
                        timeRemaining: viewModel.restTimeRemaining,
                        totalSeconds: viewModel.totalRestSeconds,
                        onAdd10: { viewModel.add10Seconds() },
                        onSub10: { viewModel.sub10Seconds() },
                        onSkip: { viewModel.skipRest() },
                        onMinimize: { viewModel.isTimerMinimized = true }
                    )
                } else {
                    VStack {
                        Spacer()
                        MinimizedTimerView(
                            timeRemaining: viewModel.restTimeRemaining,
                            onExpand: { viewModel.isTimerMinimized = false },
                            onAdd10: { viewModel.add10Seconds() },
                            onSkip: { viewModel.skipRest() }
                        )
                        .padding(.bottom, 30)
                        .allowsHitTesting(true)
                    }
                }
            }
        }
        .onAppear {
            bpmManager.startScanning()
        }
        .navigationBarHidden(true)
        .alert("¿Finalizar entrenamiento?", isPresented: $showingFinishConfirmation) {
            Button("Finalizar", role: .destructive) {
                _ = viewModel.finishWorkout(modelContext: modelContext)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("¿Estás seguro de que deseas finalizar la sesión actual?")
        }
    }

    private var workoutHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.routine.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Volumen: \(Int(viewModel.session.totalVolumeKg)) kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live BPM Pill with tap to reconnect/scan
            Button(action: {
                if bpmManager.currentBPM == 0 {
                    bpmManager.startScanning()
                } else {
                    bpmManager.reconnect()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(bpmManager.currentBPM > 0 ? .red : .gray)
                        .symbolEffect(.pulse, isActive: bpmManager.currentBPM > 0)
                    
                    if bpmManager.currentBPM > 0 {
                        Text("\(bpmManager.currentBPM) BPM")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text(bpmManager.statusText) // Usar statusText del gestor
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }
}

// MARK: - Exercise Card Component
struct ExerciseCardView: View {
    let routineExercise: RoutineExercise
    let exercise: Exercise
    let sets: [ActiveWorkoutViewModel.SetInputState]
    let onToggleSet: (Int) -> Void
    let onUpdateSet: (Int, Double, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(exercise.muscleGroup.rawValue) • \(exercise.equipmentType.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Table Header
            HStack {
                Text("SERIE")
                    .frame(width: 40, alignment: .leading)
                Text("ANTERIOR (GHOST)")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("KG")
                    .frame(width: 60, alignment: .center)
                Text("REPS")
                    .frame(width: 50, alignment: .center)
                Text("OK")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)

            Divider().background(Color.gray.opacity(0.3))

            // Set Rows
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRowView(
                    set: set,
                    onToggle: { onToggleSet(index) },
                    onUpdate: { w, r in onUpdateSet(index, w, r) }
                )
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Set Row Component
struct SetRowView: View {
    let set: ActiveWorkoutViewModel.SetInputState
    let onToggle: () -> Void
    let onUpdate: (Double, Int) -> Void

    @State private var weightString: String
    @State private var repsString: String

    init(set: ActiveWorkoutViewModel.SetInputState, onToggle: @escaping () -> Void, onUpdate: @escaping (Double, Int) -> Void) {
        self.set = set
        self.onToggle = onToggle
        self.onUpdate = onUpdate
        _weightString = State(initialValue: set.weight == 0 ? "" : String(format: "%.1f", set.weight))
        _repsString = State(initialValue: set.reps == 0 ? "" : "\(set.reps)")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Set Number
            Text("\(set.setNumber)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)

            // Ghost Reference
            Text(ghostText)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)

            // Weight Input
            TextField("0", text: $weightString)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(6)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(8)
                .frame(width: 60)
                .onChange(of: weightString) { _, newValue in
                    if let w = Double(newValue) {
                        onUpdate(w, set.reps)
                    }
                }

            // Reps Input
            TextField("0", text: $repsString)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .padding(6)
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(8)
                .frame(width: 50)
                .onChange(of: repsString) { _, newValue in
                    if let r = Int(newValue) {
                        onUpdate(set.weight, r)
                    }
                }

            // Checkmark Button
            Button(action: onToggle) {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(set.isCompleted ? .green : .gray)
            }
            .frame(width: 40, alignment: .trailing)
        }
    }

    private var ghostText: String {
        guard let gw = set.ghostWeight, let gr = set.ghostReps else { return "—" }
        return "\(String(format: "%.0f", gw))kg × \(gr)"
    }
}
