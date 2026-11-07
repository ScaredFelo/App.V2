import SwiftUI
import SwiftData

public struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    /// Sesión + rutina restauradas como una sola unidad. Si cualquiera de las
    /// dos no existe, no se presenta nada (evita el `fullScreenCover` vacío que
    /// dejaba la pantalla en negro).
    private struct RestoredWorkout: Identifiable {
        let id: UUID
        let session: WorkoutSession
        let routine: Routine
    }

    @State private var restoredWorkout: RestoredWorkout?
    @State private var didAttemptRestore = false

    public init() {}

    public var body: some View {
        TabView {
            NavigationStack {
                RoutineListView()
            }
            .tabItem {
                Label("Rutinas", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                ExerciseListView()
            }
            .tabItem {
                Label("Ejercicios", systemImage: "list.bullet")
            }

            NavigationStack {
                AnalyticsView()
            }
            .tabItem {
                Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Configuración", systemImage: "gearshape.fill")
            }
        }
        .tint(.accentColor)
        .fullScreenCover(item: $restoredWorkout) { workout in
            NavigationStack {
                ActiveWorkoutView(
                    session: workout.session,
                    routine: workout.routine,
                    modelContext: modelContext
                )
            }
            .interactiveDismissDisabled(true)
        }
        .onAppear {
            HealthKitManager.shared.requestAuthorization()
            scheduleRestoreIfNeeded()
        }
    }

    /// Si existe una sesión activa guardada (por ejemplo, tras cerrar la app
    /// por completo), abrimos directamente `ActiveWorkoutView` en el punto en
    /// el que el usuario la dejó.
    private func scheduleRestoreIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true

        // Diferimos un ciclo de runloop para que el `TabView` ya esté montado
        // y la sesión se cargue antes de presentar la vista de entrenamiento.
        Task { @MainActor in
            await Task.yield()
            guard let workout = loadRestoredWorkout() else { return }
            restoredWorkout = workout
        }
    }

    /// Carga y valida la sesión y la rutina persistidas. Devuelve `nil` de
    /// forma segura si el estado no se puede deserializar o falta algún dato.
    private func loadRestoredWorkout() -> RestoredWorkout? {
        guard let state = ActiveWorkoutStateStore.load() else { return nil }

        do {
            let sessionID = state.activeWorkoutID
            let sessionDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.id == sessionID }
            )

            guard let session = try modelContext.fetch(sessionDescriptor).first,
                  session.endDate == nil else {
                ActiveWorkoutStateStore.clear()
                return nil
            }

            let routineID = state.routineID
            let routineDescriptor = FetchDescriptor<Routine>(
                predicate: #Predicate { $0.id == routineID }
            )

            guard let routine = try modelContext.fetch(routineDescriptor).first else {
                ActiveWorkoutStateStore.clear()
                return nil
            }

            return RestoredWorkout(id: session.id, session: session, routine: routine)
        } catch {
            ActiveWorkoutStateStore.clear()
            return nil
        }
    }
}
