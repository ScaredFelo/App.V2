import ActivityKit
import Combine
import Foundation

final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    struct Snapshot {
        var exerciseName: String
        var currentSet: Int
        var totalSets: Int
        var timerStartDate: Date?
        var timerEndDate: Date?
        var isRestTimerActive: Bool
    }

    @Published private(set) var debugMessage = "Live Activity pendiente"

    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var snapshot = Snapshot(
        exerciseName: "",
        currentSet: 0,
        totalSets: 0,
        timerStartDate: nil,
        timerEndDate: nil,
        isRestTimerActive: false
    )
    private var bpm = 0
    private var isAppInBackground = false
    private let staleMargin: TimeInterval = 14_400

    private init() {}

    // MARK: - Ciclo de vida de la app

    /// La app pasa a segundo plano: conservamos intacto el estado actual de la
    /// Live Activity (incluido `timerEndDate`) para que Dynamic Island y la
    /// pantalla bloqueada no pierdan el temporizador.
    func handleScenePhaseBackground() {
        isAppInBackground = true
    }

    func handleScenePhaseActive() {
        isAppInBackground = false
    }

    func startActivity(workoutName: String, snapshot: Snapshot, bpm: Int) {
        self.snapshot = snapshot
        self.bpm = max(0, bpm)

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            currentActivity = nil
            lastState = nil
            debugMessage = "Live Activities desactivadas en Ajustes de iOS"
            print("[LiveActivity] Desactivadas en Ajustes de iOS")
            return
        }

        if let activity = currentActivity, isUsable(activity) {
            debugMessage = "Live Activity ya activa; datos actualizados"
            updateActivity(state: makeState())
            return
        }

        if let existingActivity = Activity<WorkoutActivityAttributes>.activities.first(where: { isUsable($0) }) {
            currentActivity = existingActivity
            lastState = nil
            debugMessage = "Live Activity existente reutilizada"
            updateActivity(state: makeState())
            return
        }

        do {
            currentActivity = nil
            lastState = nil
            endOrphanedActivities()

            let attributes = WorkoutActivityAttributes(workoutName: workoutName)
            let state = makeState()
            let activity = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                content: makeContent(for: state),
                pushType: nil
            )

            currentActivity = activity
            lastState = state
            debugMessage = "Live Activity iniciada correctamente"
            print("[LiveActivity] Iniciada con éxito con ID: \(activity.id)")
        } catch {
            currentActivity = nil
            lastState = nil
            debugMessage = "Error al iniciar Live Activity: \(error.localizedDescription)"
            print("[LiveActivity] ERROR al iniciar: \(error.localizedDescription)")
        }
    }

    func updateSnapshot(_ snapshot: Snapshot, bpm: Int? = nil) {
        var resolvedSnapshot = snapshot

        // Nunca borramos un temporizador que sigue vigente por una actualización
        // que llega mientras la app está en segundo plano. Si el descanso ya ha
        // vencido, sí dejamos que la Live Activity se limpie con normalidad.
        if isAppInBackground,
           !resolvedSnapshot.isRestTimerActive,
           self.snapshot.isRestTimerActive,
           let endDate = self.snapshot.timerEndDate,
           endDate > Date() {
            resolvedSnapshot.timerStartDate = self.snapshot.timerStartDate
            resolvedSnapshot.timerEndDate = endDate
            resolvedSnapshot.isRestTimerActive = true
        }

        self.snapshot = resolvedSnapshot
        if let bpm {
            self.bpm = max(0, bpm)
        }
        updateActivity(state: makeState())
    }

    func setBPM(_ bpm: Int) {
        let value = max(0, bpm)
        guard value != self.bpm else { return }
        self.bpm = value
        updateActivity(state: makeState())
    }

    func updateActivity(state: WorkoutActivityAttributes.ContentState) {
        guard let activity = currentActivity else {
            return
        }

        guard isUsable(activity) else {
            currentActivity = nil
            lastState = nil
            debugMessage = "Live Activity finalizada por el sistema"
            return
        }

        if state.isRestTimerActive, state.timerEndDate == nil {
            debugMessage = "Actualización ignorada: temporizador activo sin fecha de fin"
            return
        }

        guard lastState != state else { return }
        lastState = state

        let content = makeContent(for: state)
        Task {
            await activity.update(content)
        }
    }

    func endActivity() {
        guard let activity = currentActivity else {
            lastState = nil
            return
        }

        currentActivity = nil
        lastState = nil
        debugMessage = "Live Activity finalizada"
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func endOrphanedActivities() {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func isUsable(_ activity: Activity<WorkoutActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale:
            return true
        case .ended, .dismissed:
            return false
        @unknown default:
            return false
        }
    }

    private func makeState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: snapshot.exerciseName,
            currentSet: snapshot.currentSet,
            totalSets: snapshot.totalSets,
            timerStartDate: snapshot.timerStartDate,
            timerEndDate: snapshot.timerEndDate,
            isRestTimerActive: snapshot.isRestTimerActive,
            currentBPM: max(0, bpm)
        )
    }

    private func makeContent(
        for state: WorkoutActivityAttributes.ContentState
    ) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(staleMargin)
        )
    }
}
