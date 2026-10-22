import SwiftUI
import SwiftData

public struct ExerciseListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var selectedMuscleGroup: MuscleGroup? = nil
    @State private var selectedEquipment: EquipmentType? = nil
    @State private var searchText = ""
    @State private var showingAddModal = false

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Filter Chips
                    filterSection

                    // Exercises List
                    List {
                        ForEach(filteredExercises) { exercise in
                            ExerciseRowView(exercise: exercise)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteExercises)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Ejercicios")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingAddModal = true }) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            }
            .sheet(isPresented: $showingAddModal) {
                AddExerciseView()
            }
            .searchable(text: $searchText, prompt: "Buscar ejercicio...")
        }
    }

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                FilterChip(title: "Todos", isSelected: selectedMuscleGroup == nil && selectedEquipment == nil) {
                    selectedMuscleGroup = nil
                    selectedEquipment = nil
                }

                // Muscle Groups
                ForEach(MuscleGroup.allCases) { group in
                    FilterChip(title: group.rawValue, isSelected: selectedMuscleGroup == group) {
                        selectedMuscleGroup = (selectedMuscleGroup == group) ? nil : group
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var filteredExercises: [Exercise] {
        exercises.filter { exercise in
            let matchesSearch = searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
            let matchesMuscle = selectedMuscleGroup == nil || exercise.muscleGroup == selectedMuscleGroup
            let matchesEquipment = selectedEquipment == nil || exercise.equipmentType == selectedEquipment
            return matchesSearch && matchesMuscle && matchesEquipment
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        for index in offsets {
            let exercise = filteredExercises[index]
            modelContext.delete(exercise)
        }
        try? modelContext.save()
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color(.systemGray6).opacity(0.3))
                .foregroundColor(isSelected ? Color.black : Color.white)
                .cornerRadius(20)
        }
    }
}

// MARK: - Exercise Row
struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Label(exercise.muscleGroup.rawValue, systemImage: "figure.strengthtraining.traditional")
                    Text("•")
                    Label(exercise.equipmentType.rawValue, systemImage: "dumbbell.fill")
                    if exercise.requiresStraps {
                        Label("Recoger Straps", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}

// MARK: - Add Exercise View
public struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .pecho
    @State private var equipmentType: EquipmentType = .mancuernas
    @State private var requiresStraps = false
    @State private var restSeconds = 90
    @State private var useBpmDrop = false
    @State private var targetBpm = 110

    public var body: some View {
        NavigationStack {
            Form {
                Section("Detalles del Ejercicio") {
                    TextField("Nombre del ejercicio", text: $name)
                    Picker("Grupo Muscular", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    Picker("Equipamiento", selection: $equipmentType) {
                        ForEach(EquipmentType.allCases) { eq in
                            Text(eq.rawValue).tag(eq)
                        }
                    }
                    Toggle("Requiere Straps", isOn: $requiresStraps)
                }

                Section("Condición de Descanso") {
                    Toggle("Descanso por Bajada de BPM", isOn: $useBpmDrop)
                    if useBpmDrop {
                        Stepper("BPM Objetivo: \(targetBpm)", value: $targetBpm, in: 80...160, step: 5)
                    } else {
                        Stepper("Tiempo: \(restSeconds)s", value: $restSeconds, in: 30...300, step: 15)
                    }
                }
            }
            .navigationTitle("Nuevo Ejercicio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let restCondition: RestCondition = useBpmDrop ? .bpmDrop(targetBpm: targetBpm) : .timer(seconds: restSeconds)
                        let newExercise = Exercise(
                            name: name,
                            muscleGroup: muscleGroup,
                            equipmentType: equipmentType,
                            requiresStraps: requiresStraps,
                            defaultRestCondition: restCondition
                        )
                        modelContext.insert(newExercise)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
