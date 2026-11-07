import SwiftUI
import SwiftData

public struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var restoredSession: WorkoutSession?
    @State private var restoredRoutine: Routine?
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
        .fullScreenCover(item: $restoredSession, onDismiss: {
            restoredRoutine = nil
        }) { session in
            if let routine = restoredRoutine {
                NavigationStack {
                    ActiveWorkoutView(session: session, routine: routine, modelContext: modelContext)
                }
                .interactiveDismissDisabled(true)
            }
        }
        .onAppear {
            HealthKitManager.shared.requestAuthorization()
            restoreActiveWorkoutIfNeeded()
        }
    }

    /// Si existe una sesión activa guardada (por ejemplo, tras cerrar la app
    /// por completo), abrimos directamente `ActiveWorkoutView` en el punto en
    /// el que el usuario la dejó.
    private func restoreActiveWorkoutIfNeeded() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true

        guard let state = ActiveWorkoutStateStore.load() else { return }

        let sessionID = state.activeWorkoutID
        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == sessionID }
        )

        guard let session = try? modelContext.fetch(sessionDescriptor).first,
              session.endDate == nil else {
            ActiveWorkoutStateStore.clear()
            return
        }

        let routineID = state.routineID
        let routineDescriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == routineID }
        )

        guard let routine = try? modelContext.fetch(routineDescriptor).first else {
            ActiveWorkoutStateStore.clear()
            return
        }

        restoredRoutine = routine
        restoredSession = session
    }
}
