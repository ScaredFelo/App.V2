import SwiftUI
import SwiftData

struct ExerciseSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var exercise: Exercise

    var body: some View {
        NavigationStack {
            Form {
                Section("Ejercicio") {
                    TextField("Nombre del ejercicio", text: $exercise.name)
                }

                Section("Configuración") {
                    Picker("Tipo de peso", selection: weightTypeBinding) {
                        ForEach(WeightType.allCases) { weightType in
                            Text(weightType.rawValue).tag(weightType)
                        }
                    }

                    Picker("Grupo muscular objetivo", selection: muscleGroupBinding) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }

                    Picker("Equipamiento", selection: equipmentBinding) {
                        ForEach(EquipmentType.allCases) { equipment in
                            Text(equipment.rawValue).tag(equipment)
                        }
                    }

                    Toggle("Requiere Straps", isOn: $exercise.requiresStraps)
                }

                if exercise.requiresStraps {
                    Section {
                        Label("Recoger Straps", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .tint(.green)
            .navigationTitle("Ajustar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var weightTypeBinding: Binding<WeightType> {
        Binding(
            get: { exercise.weightType },
            set: { exercise.weightType = $0 }
        )
    }

    private var muscleGroupBinding: Binding<MuscleGroup> {
        Binding(
            get: { exercise.muscleGroup },
            set: { exercise.muscleGroup = $0 }
        )
    }

    private var equipmentBinding: Binding<EquipmentType> {
        Binding(
            get: { exercise.equipmentType },
            set: { exercise.equipmentType = $0 }
        )
    }
}
