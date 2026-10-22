import Foundation
import SwiftUI
import SwiftData

public struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ActiveWorkoutViewModel
    @State private var showingCancelConfirmation = false
    @State private var showingRoutineChangeOptions = false
    @State private var showingNewRoutineNameAlert = false
    @State private var showingExercisePicker = false
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var pendingNewRoutinePromptID: UUID?
    @State private var newRoutineName = ""

    public init(session: WorkoutSession, routine: Routine, modelContext: ModelContext) {
        _viewModel = State(initialValue: ActiveWorkoutViewModel(session: session, routine: routine, modelContext: modelContext))
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // List of exercises on the main level
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Header Status & BPM
                    workoutHeader
                        .padding(.top, 10)

                    let _ = viewModel.structureVersion

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
                                },
                                onRemove: {
                                    exercisePendingRemoval = routineExercise
                                }
                            )
                        }
                    }

                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Añadir ejercicio", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6).opacity(0.2))
                            .cornerRadius(12)
                    }

                    // Finish Workout Button
                    Button(action: {
                        if viewModel.hasWorkoutChanges {
                            showingRoutineChangeOptions = true
                        } else {
                            _ = viewModel.finishWorkout(modelContext: modelContext)
                            dismiss()
                        }
                    }) {
                        Text("Finalizar Entrenamiento")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.top, 8)

                    Button(action: {
                        showingCancelConfirmation = true
                    }) {
                        Label("Cancelar entrenamiento", systemImage: "xmark.circle")
                            .font(.subheadline.bold())
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(12)
                    }

                    // Reserva el mismo espacio inferior exista o no temporizador flotante.
                    Color.clear
                        .frame(height: 80)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }

            // Temporizador maximizado
            if viewModel.isResting && !viewModel.isTimerMinimized {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack {
                        Spacer()
                        CircularTimerView(
                            timeRemaining: viewModel.restTimeRemaining,
                            totalSeconds: viewModel.totalRestSeconds,
                            isPaused: viewModel.isRestPaused,
                            onAdd10: { viewModel.add10Seconds() },
                            onSub10: { viewModel.sub10Seconds() },
                            onTogglePause: {
                                if viewModel.isRestPaused {
                                    viewModel.resumeRest()
                                } else {
                                    viewModel.pauseRest()
                                }
                            },
                            onSkip: { viewModel.skipRest() },
                            onMinimize: { viewModel.isTimerMinimized = true }
                        )
                        Spacer()
                    }
                }
                .zIndex(2)
            }

            // Temporizador minimizado flotando sobre la lista
            if viewModel.isResting && viewModel.isTimerMinimized {
                MinimizedTimerView(
                    timeRemaining: viewModel.restTimeRemaining,
                    isPaused: viewModel.isRestPaused,
                    onExpand: { viewModel.isTimerMinimized = false },
                    onTogglePause: {
                        if viewModel.isRestPaused {
                            viewModel.resumeRest()
                        } else {
                            viewModel.pauseRest()
                        }
                    },
                    onAdd10: { viewModel.add10Seconds() },
                    onSub10: { viewModel.sub10Seconds() },
                    onSkip: { viewModel.skipRest() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isTimerMinimized)
        .onAppear {
            BPMManager.shared.startScanning()
        }
        .onDisappear {
            pendingNewRoutinePromptID = nil
        }
        .navigationBarHidden(true)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                _ = viewModel.addExercise(exercise, modelContext: modelContext)
            }
        }
        .alert("¿Guardar cambios?", isPresented: $showingRoutineChangeOptions) {
            Button("Reemplazar rutina actual", role: .destructive) {
                _ = viewModel.finishWorkoutReplacingRoutine(modelContext: modelContext)
                dismiss()
            }
            Button("Guardar como nueva rutina") {
                newRoutineName = "\(viewModel.routine.name) (modificada)"
                let promptID = UUID()
                pendingNewRoutinePromptID = promptID

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard pendingNewRoutinePromptID == promptID else { return }
                    showingNewRoutineNameAlert = true
                }
            }
            Button("Guardar solo el historial de hoy") {
                _ = viewModel.finishWorkoutHistoryOnly(modelContext: modelContext)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Has añadido, quitado o modificado datos respecto a la rutina original. ¿Qué quieres hacer con los cambios?")
        }
        .alert("Nueva rutina", isPresented: $showingNewRoutineNameAlert) {
            TextField("Nombre de la rutina", text: $newRoutineName)
            Button("Guardar") {
                _ = viewModel.finishWorkoutSavingAsNewRoutine(named: newRoutineName, modelContext: modelContext)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se guardará una copia con los cambios de hoy.")
        }
        .alert("¿Cancelar entrenamiento?", isPresented: $showingCancelConfirmation) {
            Button("Cancelar entrenamiento", role: .destructive) {
                pendingNewRoutinePromptID = nil
                showingRoutineChangeOptions = false
                showingNewRoutineNameAlert = false
                viewModel.cancelWorkout(modelContext: modelContext)
                dismiss()
            }
            Button("Seguir entrenando", role: .cancel) {}
        } message: {
            Text("Se descartará la sesión actual sin guardar el historial.")
        }
        .alert(
            "Eliminar ejercicio",
            isPresented: Binding(
                get: { exercisePendingRemoval != nil },
                set: { if !$0 { exercisePendingRemoval = nil } }
            )
        ) {
            Button("Eliminar", role: .destructive) {
                if let routineExercise = exercisePendingRemoval {
                    viewModel.removeExercise(routineExercise, modelContext: modelContext)
                }
                exercisePendingRemoval = nil
            }
            Button("Cancelar", role: .cancel) { exercisePendingRemoval = nil }
        } message: {
            Text("El ejercicio se quitará del entrenamiento actual.")
        }
    }

    private var workoutHeader: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(viewModel.routine.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(Int(viewModel.session.totalVolumeKg)) kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 44)

            HStack {
                Button {
                    showingCancelConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray6).opacity(0.3))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Cancelar entrenamiento")

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Exercise Card Component
struct ExerciseCardView: View {
    let routineExercise: RoutineExercise
    let exercise: Exercise
    let sets: [ActiveWorkoutViewModel.SetInputState]
    let onToggleSet: (Int) -> Void
    let onUpdateSet: (Int, Double, Int) -> Void
    let onRemove: () -> Void

    @State private var notesExpanded = false

    private var notesBinding: Binding<String> {
        Binding(
            get: { routineExercise.notes },
            set: { routineExercise.notes = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(exercise.muscleGroup.rawValue) • \(exercise.equipmentType.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if exercise.requiresStraps {
                        Label("Recoger Straps", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red.opacity(0.9))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Eliminar ejercicio")
            }

            // Table Header
            HStack {
                Text("SERIE")
                    .frame(width: 40, alignment: .center)
                Text("ANTERIOR (GHOST)")
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("KG")
                    .frame(width: 60, alignment: .center)
                Text("REPS")
                    .frame(width: 50, alignment: .center)
                Text("OK")
                    .frame(width: 32, alignment: .center)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)

            Divider().background(Color.gray.opacity(0.3))

            // Set Rows
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                SetRowView(
                    set: set,
                    onToggle: { onToggleSet(index) },
                    onUpdate: { w, r in onUpdateSet(index, w, r) }
                )
            }

            Divider().background(Color.gray.opacity(0.3))

            DisclosureGroup(isExpanded: $notesExpanded) {
                TextField("Consejos, altura de poleas, agarre...", text: notesBinding, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(2...6)
                    .padding(10)
                    .background(Color(.systemGray6).opacity(0.2))
                    .cornerRadius(10)
            } label: {
                Label("Notas", systemImage: "note.text")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
                .frame(width: 40, alignment: .center)
                .multilineTextAlignment(.center)

            // Ghost Reference
            Text(ghostText)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

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
                    .font(.body)
                    .foregroundStyle(set.isCompleted ? .green : .gray)
                    .frame(width: 30, height: 28)
            }
            .frame(width: 32, alignment: .center)
            .accessibilityLabel(set.isCompleted ? "Serie completada" : "Marcar serie como completada")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(set.isCompleted ? Color.green.opacity(0.12) : Color.clear)
        .cornerRadius(8)
    }

    private var ghostText: String {
        guard let gw = set.ghostWeight, let gr = set.ghostReps else { return "—" }
        return "\(String(format: "%.0f", gw))kg × \(gr)"
    }
}
