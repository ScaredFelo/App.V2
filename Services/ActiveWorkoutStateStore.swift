import Foundation

// MARK: - Persistencia de la sesión de entrenamiento activa

struct PersistedWorkoutSet: Codable, Hashable {
    var routineExerciseID: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var date: Date
}

struct PersistedWorkoutState: Codable, Hashable {
    var activeWorkoutID: UUID
    var routineID: UUID
    var workoutStartDate: Date
    var completedSets: [PersistedWorkoutSet]
    var restTimerEndDate: Date?

    // Estado auxiliar para reanudar el temporizador exactamente donde se quedó.
    var timerStartDate: Date?
    var totalRestSeconds: Int
    var restTimeRemaining: Int
    var isResting: Bool
    var isRestPaused: Bool
    var isRestTimerActive: Bool
    var isTimerMinimized: Bool
    var restCondition: RestCondition?
    var restTargetBpm: Int?
    var currentExerciseName: String
    var currentRestModeTitle: String
    var restingSetNumber: Int
    var restingTotalSets: Int

    var updatedAt: Date
}

enum ActiveWorkoutStateStore {
    private static let storageKey = "activeWorkoutState.v1"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func save(_ state: PersistedWorkoutState) {
        guard let data = try? encoder.encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func load() -> PersistedWorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(PersistedWorkoutState.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static var hasActiveWorkout: Bool {
        load() != nil
    }
}
