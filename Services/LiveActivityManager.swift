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
    private let staleMargin: TimeInterval = 14_400

    private init() {}

    func startActivity(workoutName: String, snapshot: Snapshot, bpm: Int) {
        self.snapshot = snapshot
        self.bpm = max(0, bpm)

        if let activity = currentActivity, isUsable(activity) {
            debugMessage = "Live Activity ya activa; datos actualizados"
            updateActivity(state: makeState())
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            currentActivity = nil
            lastState = nil
            debugMessage = "Live Activities desactivadas en Ajustes de iOS"
            print("[LiveActivity] Desactivadas en Ajustes de iOS")
            return
        }

        do {
            if let previousActivity = currentActivity {
                Task { await previousActivity.end(nil, dismissalPolicy: .immediate) }
                currentActivity = nil
                lastState = nil
            }

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
        self.snapshot = snapshot
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

        if let lastState, lastState == state {
            return
        }
        lastState = state

        Task {
            await activity.update(makeContent(for: state))
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
