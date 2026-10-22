import Foundation
import SwiftData

@MainActor
public enum MockDataGenerator {
    public static func seedIfNeeded(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<Exercise>()
            let existingCount = try context.fetchCount(descriptor)
            guard existingCount == 0 else { return }

            // Ejercicios Base
            let benchPress = Exercise(
                name: "Press de Banca con Barra",
                muscleGroup: .pecho,
                equipmentType: .barraOlimpica,
                requiresStraps: false,
                defaultRestCondition: .timer(seconds: 120)
            )

            let pullUps = Exercise(
                name: "Dominadas Lastradas",
                muscleGroup: .espalda,
                equipmentType: .barraFija,
                requiresStraps: true,
                defaultRestCondition: .timer(seconds: 90)
            )

            let squat = Exercise(
                name: "Sentadilla Libre",
                muscleGroup: .cuadriceps,
                equipmentType: .barraOlimpica,
                requiresStraps: false,
                defaultRestCondition: .bpmDrop(targetBpm: 110)
            )

            let bicepCurl = Exercise(
                name: "Curl con Mancuernas",
                muscleGroup: .biceps,
                equipmentType: .mancuernas,
                requiresStraps: false,
                defaultRestCondition: .timer(seconds: 60)
            )

            let tricepPushdown = Exercise(
                name: "Extensiones en Polea",
                muscleGroup: .triceps,
                equipmentType: .poleas,
                requiresStraps: false,
                defaultRestCondition: .timer(seconds: 60)
            )

            context.insert(benchPress)
            context.insert(pullUps)
            context.insert(squat)
            context.insert(bicepCurl)
            context.insert(tricepPushdown)

            // Rutinas Plantilla
            let upperBodyRoutine = Routine(
                name: "Torso Superior Hipertrofia",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: benchPress, defaultSets: 4, targetReps: 8, sortOrder: 0),
                    RoutineExercise(exercise: pullUps, defaultSets: 3, targetReps: 10, sortOrder: 1),
                    RoutineExercise(exercise: bicepCurl, defaultSets: 3, targetReps: 12, sortOrder: 2),
                    RoutineExercise(exercise: tricepPushdown, defaultSets: 3, targetReps: 12, sortOrder: 3)
                ]
            )

            let lowerBodyRoutine = Routine(
                name: "Pierna Completa Fuerza",
                isTemplate: true,
                exercises: [
                    RoutineExercise(exercise: squat, defaultSets: 5, targetReps: 5, sortOrder: 0)
                ]
            )

            context.insert(upperBodyRoutine)
            context.insert(lowerBodyRoutine)

            try context.save()
        } catch {
            print("Error seeding mock data: \(error)")
        }
    }
}
