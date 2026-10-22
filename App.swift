import SwiftUI
import SwiftData

@main
struct AppGymApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                Exercise.self,
                Routine.self,
                RoutineExercise.self,
                WorkoutSession.self,
                WorkoutSetLog.self
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
            
            // Seed initial mock data
            Task { @MainActor in
                let context = container.mainContext
                MockDataGenerator.seedIfNeeded(context: context)
            }
        } catch {
            fatalError("Failed to configure SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    @Query private var routines: [Routine]

    var body: some View {
        NavigationStack {
            List {
                Section("Ejercicios Disponibles (\(exercises.count))") {
                    ForEach(exercises) { exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.headline)
                            HStack {
                                Text(exercise.muscleGroup.rawValue)
                                Text("•")
                                Text(exercise.equipmentType.rawValue)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Rutinas Plantilla (\(routines.count))") {
                    ForEach(routines) { routine in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(routine.name)
                                .font(.headline)
                            Text("\(routine.exercises.count) ejercicios")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("App.gym")
        }
    }
}
