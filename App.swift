import SwiftUI
import SwiftData

@main
struct AppGymApp: App {
    let container: ModelContainer
    @StateObject private var bpmManager = BPMManager.shared

    init() {
        do {
            let schema = Schema([
                Exercise.self,
                Routine.self,
                RoutineExercise.self,
                WorkoutSession.self,
                WorkoutSetLog.self
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(bpmManager)
                .onAppear {
                    let context = container.mainContext
                    MockDataGenerator.seedIfNeeded(context: context)
                }
        }
        .modelContainer(container)
    }
}
