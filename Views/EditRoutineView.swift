import SwiftUI
import SwiftData

struct EditRoutineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var routine: Routine
    let isNewRoutine: Bool

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var showingExercisePicker = false
    @State private var exercisePendingRemoval: RoutineExercise?
    @State private var exerciseToConfigure: Exercise?

    private var sortedExercises: [RoutineExercise] {
        routine.exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MODO EDICIÓN")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                        Text("Los cambios se guardan en esta rutina, no en el entrenamiento activo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Nombre de la rutina") {
                TextField("Nombre", text: $routine.name)
            }

            if sortedExercises.isEmpty {
                Section {
                    Text("Todavía no hay ejercicios. Añade el primero para empezar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(sortedExercises.enumerated()), id: \.element.id) { index, routineExercise in
                    Section {
                        RoutineExerciseEditorRow(
                            routineExercise: routineExercise,
                            exercises: exercises
                        )
                    } header: {
                        HStack {
                            Text("Ejercicio \(index + 1)")
                            Spacer()
                            Button(role: .destructive) {
                                exercisePendingRemoval = routineExercise
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Eliminar ejercicio")
                        }
                    }
                }
            }

            Section {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Añadir ejercicio", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(.green)
        .navigationTitle("Editar rutina")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    discardNewRoutineIfNeeded()
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    ForEach(sortedExercises) { routineExercise in
                        if let exercise = routineExercise.exercise {
                            Button {
                                exerciseToConfigure = exercise
                            } label: {
                                Label(exercise.name, systemImage: "gearshape")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .disabled(sortedExercises.isEmpty)
                .accessibilityLabel("Ajustar ejercicio")

                Button("Guardar") {
                    if isNewRoutine && routine.modelContext == nil {
                        modelContext.insert(routine)
                    }
                    try? modelContext.save()
                    dismiss()
                }
                .fontWeight(.bold)
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                let nextOrder = (routine.exercises.map(\.sortOrder).max() ?? -1) + 1
                let routineExercise = RoutineExercise(exercise: exercise, sortOrder: nextOrder)
                if !isNewRoutine {
                    modelContext.insert(routineExercise)
                }
                routine.exercises.append(routineExercise)
                if !isNewRoutine {
                    try? modelContext.save()
                }
            }
        }
        .sheet(item: $exerciseToConfigure) { exercise in
            ExerciseSettingsView(exercise: exercise)
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
                    routine.exercises.removeAll { $0.id == routineExercise.id }
                    if !isNewRoutine {
                        modelContext.delete(routineExercise)
                    }
                    normalizeSortOrder()
                    if !isNewRoutine {
                        try? modelContext.save()
                    }
                }
                exercisePendingRemoval = nil
            }
            Button("Cancelar", role: .cancel) { exercisePendingRemoval = nil }
        } message: {
            Text("Este ejercicio se quitará de la rutina.")
        }
    }

    private func normalizeSortOrder() {
        for (index, routineExercise) in routine.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            routineExercise.sortOrder = index
        }
    }

    private func discardNewRoutineIfNeeded() {
        guard isNewRoutine, routine.modelContext != nil else { return }
        modelContext.delete(routine)
        try? modelContext.save()
    }
}

private struct RoutineExerciseEditorRow: View {
    @Bindable var routineExercise: RoutineExercise
    let exercises: [Exercise]

    @State private var notesExpanded = false

    private var exerciseNameBinding: Binding<String> {
        Binding(
            get: { routineExercise.exercise?.name ?? "" },
            set: { routineExercise.exercise?.name = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Nombre del ejercicio", text: exerciseNameBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(routineExercise.exercise == nil)

                Menu {
                    ForEach(exercises) { exercise in
                        Button {
                            routineExercise.exercise = exercise
                        } label: {
                            if routineExercise.exercise?.id == exercise.id {
                                Label(exercise.name, systemImage: "checkmark")
                            } else {
                                Text(exercise.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                        .frame(width: 32, height: 32)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cambiar ejercicio")
            }

            if let exercise = routineExercise.exercise {
                HStack(spacing: 10) {
                    Label(exercise.muscleGroup.rawValue, systemImage: "figure.strengthtraining.traditional")
                    Label(exercise.equipmentType.rawValue, systemImage: "dumbbell.fill")
                    if exercise.requiresStraps {
                        Label("Straps", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Stepper("Series: \(routineExercise.defaultSets)", value: $routineExercise.defaultSets, in: 1...12)
            Stepper("Repeticiones: \(routineExercise.targetReps)", value: $routineExercise.targetReps, in: 1...50)

            HStack {
                Text("Peso por defecto")
                Spacer()
                TextField("0", value: $routineExercise.defaultWeight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg")
                    .foregroundStyle(.secondary)
            }

            Stepper("Descanso: \(routineExercise.restSeconds)s", value: $routineExercise.restSeconds, in: 0...600, step: 15)

            if routineExercise.exercise?.requiresStraps == true {
                Label("Recoger Straps", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            DisclosureGroup("Notas", isExpanded: $notesExpanded) {
                TextField(
                    "Consejos, altura de poleas, agarre...",
                    text: $routineExercise.notes,
                    axis: .vertical
                )
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
            }
            .font(.subheadline.bold())
        }
        .padding(.vertical, 4)
    }
}
