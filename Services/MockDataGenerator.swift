import Foundation
import SwiftData

@MainActor
public final class MockDataGenerator {
    public static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Exercise>()
            let existingCount = try context.fetchCount(descriptor)
            guard existingCount == 0 else { return }

            // Helper to map muscle groups securely
            func muscle(for name: String) -> MuscleGroup {
                let lower = name.lowercased()
                if lower.contains("pecho") { return .pecho }
                if lower.contains("espalda") { return .espalda }
                if lower.contains("hombro") { return .hombros }
                if lower.contains("biceps") { return .biceps }
                if lower.contains("triceps") { return .triceps }
                if lower.contains("cuadriceps") || lower.contains("cuádriceps") { return .cuadriceps }
                if lower.contains("isquio") { return .isquios }
                if lower.contains("gemelo") { return .gemelos }
                if lower.contains("gluteo") { return .gluteos }
                return .pecho
            }

            // Helper to map equipment securely
            func equipment(for name: String) -> EquipmentType {
                let lower = name.lowercased()
                if lower.contains("multipower") || lower.contains("smith") { return .multipower }
                if lower.contains("cable") || lower.contains("polea") { return .poleas }
                if lower.contains("mancuerna") { return .mancuernas }
                if lower.contains("barra olímpica") || lower.contains("barra libre") { return .barraOlimpica }
                if lower.contains("disco") || lower.contains("maquina") || lower.contains("máquina") { return .discosMaquina }
                return .mancuernas
            }

            // --- PUSH EXERCISES ---
            let push1 = Exercise(name: "Press banca inclinado", muscleGroup: muscle(for: "Pecho"), equipmentType: equipment(for: "Multipower (smith)"), defaultRestCondition: .timer(seconds: 135))
            let push2 = Exercise(name: "Elevaciones laterales mancuerna", muscleGroup: muscle(for: "Hombro lateral"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))
            let push3 = Exercise(name: "Triceps pushdowns", muscleGroup: muscle(for: "Tríceps"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))
            let push4 = Exercise(name: "Seated cable fly", muscleGroup: muscle(for: "Pecho"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))
            let push5 = Exercise(name: "Press militar", muscleGroup: muscle(for: "Hombro frontal"), equipmentType: equipment(for: "Mancuernas"), defaultRestCondition: .timer(seconds: 135))
            let push6 = Exercise(name: "Extension de triceps", muscleGroup: muscle(for: "Tríceps"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))

            context.insert(push1)
            context.insert(push2)
            context.insert(push3)
            context.insert(push4)
            context.insert(push5)
            context.insert(push6)

            let pushRoutine = Routine(
                name: "PUSH",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: push1, defaultSets: 3, targetReps: 8, sortOrder: 0),
                    RoutineExercise(exercise: push2, defaultSets: 3, targetReps: 10, sortOrder: 1),
                    RoutineExercise(exercise: push3, defaultSets: 3, targetReps: 9, sortOrder: 2),
                    RoutineExercise(exercise: push4, defaultSets: 2, targetReps: 10, sortOrder: 3),
                    RoutineExercise(exercise: push5, defaultSets: 2, targetReps: 8, sortOrder: 4),
                    RoutineExercise(exercise: push6, defaultSets: 2, targetReps: 10, sortOrder: 5)
                ]
            )
            context.insert(pushRoutine)

            // --- PULL EXERCISES ---
            let pull1 = Exercise(name: "Jalon al pecho", muscleGroup: muscle(for: "Espalda"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))
            let pull2 = Exercise(name: "Curl bayesiano", muscleGroup: muscle(for: "Biceps"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))
            let pull3 = Exercise(name: "Remo en maquina", muscleGroup: muscle(for: "Espalda"), equipmentType: equipment(for: "Discos para máquina"), defaultRestCondition: .timer(seconds: 135))
            let pull4 = Exercise(name: "Spider curl", muscleGroup: muscle(for: "Biceps"), equipmentType: equipment(for: "Mancuernas"), defaultRestCondition: .timer(seconds: 135))
            let pull5 = Exercise(name: "Remo libre", muscleGroup: muscle(for: "Espalda"), equipmentType: equipment(for: "Barra olímpica"), defaultRestCondition: .timer(seconds: 135))
            let pull6 = Exercise(name: "Isolateral reverse fly", muscleGroup: muscle(for: "Hombro posterior"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 135))

            context.insert(pull1)
            context.insert(pull2)
            context.insert(pull3)
            context.insert(pull4)
            context.insert(pull5)
            context.insert(pull6)

            let pullRoutine = Routine(
                name: "PULL",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: pull1, defaultSets: 3, targetReps: 8, sortOrder: 0),
                    RoutineExercise(exercise: pull2, defaultSets: 3, targetReps: 10, sortOrder: 1),
                    RoutineExercise(exercise: pull3, defaultSets: 2, targetReps: 9, sortOrder: 2),
                    RoutineExercise(exercise: pull4, defaultSets: 2, targetReps: 10, sortOrder: 3),
                    RoutineExercise(exercise: pull5, defaultSets: 2, targetReps: 9, sortOrder: 4),
                    RoutineExercise(exercise: pull6, defaultSets: 3, targetReps: 10, sortOrder: 5)
                ]
            )
            context.insert(pullRoutine)

            // --- LEGS EXERCISES ---
            let leg1 = Exercise(name: "Hiperextensiones", muscleGroup: muscle(for: "Espalda"), equipmentType: equipment(for: "Discos para máquina"), defaultRestCondition: .timer(seconds: 180))
            let leg2 = Exercise(name: "Flexion de pierna estirado", muscleGroup: muscle(for: "Isquiotibiales"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 180))
            let leg3 = Exercise(name: "Bulgaras", muscleGroup: muscle(for: "Cuádriceps"), equipmentType: equipment(for: "Mancuernas"), defaultRestCondition: .timer(seconds: 180))
            let leg4 = Exercise(name: "Elevacion talones sentado", muscleGroup: muscle(for: "Gemelos"), equipmentType: equipment(for: "Discos para máquina"), defaultRestCondition: .timer(seconds: 180))
            let leg5 = Exercise(name: "Romanian deadlift (RDL)", muscleGroup: muscle(for: "Isquiotibiales"), equipmentType: equipment(for: "Barra olímpica"), defaultRestCondition: .timer(seconds: 180))
            let leg6 = Exercise(name: "Extension de quadriceps", muscleGroup: muscle(for: "Cuádriceps"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 180))

            context.insert(leg1)
            context.insert(leg2)
            context.insert(leg3)
            context.insert(leg4)
            context.insert(leg5)
            context.insert(leg6)

            let legsRoutine = Routine(
                name: "LEGS",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: leg1, defaultSets: 2, targetReps: 10, sortOrder: 0),
                    RoutineExercise(exercise: leg2, defaultSets: 3, targetReps: 8, sortOrder: 1),
                    RoutineExercise(exercise: leg3, defaultSets: 2, targetReps: 9, sortOrder: 2),
                    RoutineExercise(exercise: leg4, defaultSets: 2, targetReps: 10, sortOrder: 3),
                    RoutineExercise(exercise: leg5, defaultSets: 2, targetReps: 8, sortOrder: 4),
                    RoutineExercise(exercise: leg6, defaultSets: 2, targetReps: 10, sortOrder: 5)
                ]
            )
            context.insert(legsRoutine)

            // --- UPPER ROUTINE ---
            let upperRoutine = Routine(
                name: "UPPER",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: push1, defaultSets: 3, targetReps: 8, sortOrder: 0),
                    RoutineExercise(exercise: push4, defaultSets: 2, targetReps: 10, sortOrder: 1),
                    RoutineExercise(exercise: pull1, defaultSets: 3, targetReps: 8, sortOrder: 2),
                    RoutineExercise(exercise: push2, defaultSets: 2, targetReps: 10, sortOrder: 3),
                    RoutineExercise(exercise: pull5, defaultSets: 2, targetReps: 9, sortOrder: 4),
                    RoutineExercise(exercise: push6, defaultSets: 2, targetReps: 10, sortOrder: 5),
                    RoutineExercise(exercise: pull2, defaultSets: 2, targetReps: 10, sortOrder: 6),
                    RoutineExercise(exercise: pull6, defaultSets: 2, targetReps: 10, sortOrder: 7)
                ]
            )
            context.insert(upperRoutine)

            // --- LOWER ROUTINE ---
            let leg7 = Exercise(name: "Flexion de pierna sentado", muscleGroup: muscle(for: "Isquiotibiales"), equipmentType: equipment(for: "Cables (poleas)"), defaultRestCondition: .timer(seconds: 180))

            context.insert(leg7)

            let lowerRoutine = Routine(
                name: "LOWER",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: leg1, defaultSets: 2, targetReps: 10, sortOrder: 0),
                    RoutineExercise(exercise: leg7, defaultSets: 3, targetReps: 8, sortOrder: 1),
                    RoutineExercise(exercise: leg3, defaultSets: 2, targetReps: 9, sortOrder: 2),
                    RoutineExercise(exercise: leg4, defaultSets: 2, targetReps: 10, sortOrder: 3),
                    RoutineExercise(exercise: leg5, defaultSets: 2, targetReps: 8, sortOrder: 4),
                    RoutineExercise(exercise: leg6, defaultSets: 2, targetReps: 10, sortOrder: 5)
                ]
            )
            context.insert(lowerRoutine)

            try context.save()
        } catch {
            print("Error seeding mock data: \(error)")
        }
    }
}
