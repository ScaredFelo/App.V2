import SwiftUI
import SwiftData
import UserNotifications

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
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("No se pudo crear el ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    // Solicitar notificaciones explícitamente para Live Activities
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if let error = error {
                            print("Error notificaciones: \(error.localizedDescription)")
                        }
                    }
                    let context = container.mainContext
                    MockDataGenerator.seedIfNeeded(context: context)
                }
        }
        .modelContainer(container)
    }
}
