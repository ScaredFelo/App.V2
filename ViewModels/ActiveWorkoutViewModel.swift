import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
public final class ActiveWorkoutViewModel {
    public var session: WorkoutSession
    public var routine: Routine
    public var activeSets: [UUID: [SetInputState]] = [:]
    public var structureVersion = 0

    // Rest Timer State
    public var isResting = false
    public var isRestPaused = false
    public var restTimeRemaining = 0
    public var totalRestSeconds = 0
    public var restTimerEndDate: Date? = nil
    public var isRestTimerActive: Bool = false
    public var restTargetBpm: Int?
    public var currentRestModeTitle = ""
    public var currentExerciseName = ""
    public var timerStartDate: Date?
    public var timerTargetDuration = 0
    public var isTimerMinimized: Bool = false
    public var isRestFinishing: Bool = false

    public var hasActiveRestTimer: Bool {
        guard let endDate = restTimerEndDate else { return false }
        return endDate > Date()
    }

    private var timerTask: Task<Void, Never>?
    private var bpmObserverTask: Task<Void, Never>?
    private var restDismissalTask: Task<Void, Never>?
    private var didStartWorkoutActivity = false
    private var restingSetNumber = 0
    private var restingTotalSets = 0
    private var currentRestCondition: RestCondition?

    private var originalRoutineExercises: [RoutineExercise] = []
    private var originalSnapshots: [RoutineSnapshot] = []
    private var addedRoutineExerciseIDs: Set<UUID> = []
    private var removedRoutineExercises: [RoutineExercise] = []

    private struct RoutineSnapshot {
        let id: UUID
        let exercise: Exercise?
        let defaultSets: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let sortOrder: Int
        let defaultWeight: Double
        let restSeconds: Int
        let notes: String
    }

    public struct SetInputState: Identifiable {
        public let id = UUID()
        public let setNumber: Int
        public var weight: Double
        public var reps: Int
        public var isCompleted: Bool
        public var ghostWeight: Double?
        public var ghostReps: Int?
        public var existingLog: WorkoutSetLog?
    }

    public init(session: WorkoutSession, routine: Routine, modelContext: ModelContext) {
        self.session = session
        self.routine = routine
        setupInitialSets(modelContext: modelContext)
        captureOriginalStructure()
        HealthKitManager.shared.requestAuthorization()
        let hasStoredStateForSession = ActiveWorkoutStateStore.load()?.activeWorkoutID == session.id
        restorePersistedStateIfNeeded(modelContext: modelContext)
        if !hasStoredStateForSession {
            persistState()
        }
    }

    // MARK: - Exercise Structure

    private func setupInitialSets(modelContext: ModelContext) {
        for routineExercise in routine.exercises {
            activeSets[routineExercise.id] = buildSetStates(for: routineExercise, modelContext: modelContext)
        }
    }

    private func buildSetStates(for routineExercise: RoutineExercise, modelContext: ModelContext) -> [SetInputState] {
        guard let exercise = routineExercise.exercise else { return [] }

        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<WorkoutSetLog>(
            predicate: #Predicate { (log: WorkoutSetLog) -> Bool in
                return log.exercise?.id == exerciseID
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let allLogs = (try? modelContext.fetch(descriptor)) ?? []

        // Historial de referencia: solo entrenamientos anteriores (nunca la
        // sesión en curso) y, preferentemente, de esta misma variante de rutina.
        let sessionID: UUID = session.id
        let previousLogs = allLogs.filter { (log: WorkoutSetLog) -> Bool in
            guard log.isCompleted else { return false }
            guard log.session?.id != sessionID else { return false }
            guard log.date < session.startDate else { return false }
            guard let logRoutineExerciseID: UUID = log.routineExerciseID else { return true }
            return logRoutineExerciseID == routineExercise.id
        }

        // Para la parrilla de Big Picture solo cuenta la última sesión previa.
        let lastSessionLogs: [WorkoutSetLog]
        if let latestSessionID: UUID = previousLogs.first?.session?.id {
            lastSessionLogs = previousLogs.filter { (log: WorkoutSetLog) -> Bool in
                return log.session?.id == latestSessionID
            }
        } else {
            lastSessionLogs = previousLogs
        }

        let currentLogs = session.setsCompleted.filter { (log: WorkoutSetLog) -> Bool in
            return log.exercise?.id == exerciseID && log.isCompleted
        }
        var legacyLogs = currentLogs
            .filter { (log: WorkoutSetLog) -> Bool in
                return log.routineExerciseID == nil
            }
            .sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                return lhs.date < rhs.date
            }
        var sets: [SetInputState] = []

        for i in 1...max(1, routineExercise.defaultSets) {
            let stableLog = currentLogs.first {
                $0.routineExerciseID == routineExercise.id && $0.setNumber == i
            }
            let legacyLog: WorkoutSetLog?
            if stableLog == nil, !legacyLogs.isEmpty {
                legacyLog = legacyLogs.removeFirst()
            } else {
                legacyLog = nil
            }
            let currentLog = stableLog ?? legacyLog

            let matchingLog = lastSessionLogs.first { $0.setNumber == i }
                ?? (lastSessionLogs.indices.contains(i - 1) ? lastSessionLogs[i - 1] : nil)
            let ghostW = matchingLog?.weight
            let ghostR = matchingLog?.reps
            let initialWeight = routineExercise.defaultWeight > 0 ? routineExercise.defaultWeight : (ghostW ?? 0.0)
            let initialReps = routineExercise.targetRepsMax

            sets.append(SetInputState(
                setNumber: i,
                weight: currentLog?.weight ?? initialWeight,
                reps: currentLog?.reps ?? initialReps,
                isCompleted: currentLog != nil,
                ghostWeight: ghostW,
                ghostReps: ghostR,
                existingLog: currentLog
            ))
        }

        return sets
    }

    @discardableResult
    public func addExercise(_ exercise: Exercise, modelContext: ModelContext) -> RoutineExercise {
        let nextOrder = (routine.exercises.map(\.sortOrder).max() ?? -1) + 1
        let routineExercise = RoutineExercise(
            exercise: exercise,
            targetRepsMin: exercise.targetRepsMin,
            targetRepsMax: exercise.targetRepsMax,
            sortOrder: nextOrder
        )

        modelContext.insert(routineExercise)
        routine.exercises.append(routineExercise)
        activeSets[routineExercise.id] = buildSetStates(for: routineExercise, modelContext: modelContext)
        addedRoutineExerciseIDs.insert(routineExercise.id)
        structureVersion += 1
        try? modelContext.save()
        persistState()

        return routineExercise
    }

    public func removeExercise(_ routineExercise: RoutineExercise, modelContext: ModelContext) {
        guard routine.exercises.contains(where: { $0.id == routineExercise.id }) else { return }

        routine.exercises.removeAll { $0.id == routineExercise.id }
        activeSets.removeValue(forKey: routineExercise.id)

        if addedRoutineExerciseIDs.contains(routineExercise.id) {
            addedRoutineExerciseIDs.remove(routineExercise.id)
            modelContext.delete(routineExercise)
        } else if !removedRoutineExercises.contains(where: { $0.id == routineExercise.id }) {
            removedRoutineExercises.append(routineExercise)
        }

        normalizeSortOrder()
        structureVersion += 1
        try? modelContext.save()
        persistState()
    }

    private func normalizeSortOrder() {
        for (index, routineExercise) in routine.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
            routineExercise.sortOrder = index
        }
    }

    private func captureOriginalStructure() {
        originalRoutineExercises = routine.exercises.sorted { $0.sortOrder < $1.sortOrder }
        originalSnapshots = originalRoutineExercises.map {
            RoutineSnapshot(
                id: $0.id,
                exercise: $0.exercise,
                defaultSets: $0.defaultSets,
                targetRepsMin: $0.targetRepsMin,
                targetRepsMax: $0.targetRepsMax,
                sortOrder: $0.sortOrder,
                defaultWeight: $0.defaultWeight,
                restSeconds: $0.restSeconds,
                notes: $0.notes
            )
        }
    }

    public var hasRoutineChanged: Bool {
        let current = routine.exercises.sorted { $0.sortOrder < $1.sortOrder }
        guard current.count == originalSnapshots.count else { return true }

        let snapshotsByID = Dictionary(uniqueKeysWithValues: originalSnapshots.map { ($0.id, $0) })

        for routineExercise in current {
            guard let snapshot = snapshotsByID[routineExercise.id] else { return true }
            if routineExercise.exercise?.id != snapshot.exercise?.id ||
                routineExercise.defaultSets != snapshot.defaultSets ||
                routineExercise.targetRepsMin != snapshot.targetRepsMin ||
                routineExercise.targetRepsMax != snapshot.targetRepsMax ||
                routineExercise.sortOrder != snapshot.sortOrder ||
                routineExercise.defaultWeight != snapshot.defaultWeight ||
                routineExercise.restSeconds != snapshot.restSeconds ||
                routineExercise.notes != snapshot.notes {
                return true
            }
        }

        return false
    }

    public var hasWorkoutChanges: Bool {
        hasRoutineChanged
    }

    private func restoreOriginalStructure(modelContext: ModelContext) {
        let currentExercises = routine.exercises
        for routineExercise in currentExercises where addedRoutineExerciseIDs.contains(routineExercise.id) {
            modelContext.delete(routineExercise)
            activeSets.removeValue(forKey: routineExercise.id)
        }

        for snapshot in originalSnapshots {
            guard let routineExercise = originalRoutineExercises.first(where: { $0.id == snapshot.id }) else { continue }
            routineExercise.exercise = snapshot.exercise
            routineExercise.defaultSets = snapshot.defaultSets
            routineExercise.targetRepsMin = snapshot.targetRepsMin
            routineExercise.targetRepsMax = snapshot.targetRepsMax
            routineExercise.sortOrder = snapshot.sortOrder
            routineExercise.defaultWeight = snapshot.defaultWeight
            routineExercise.restSeconds = snapshot.restSeconds
            routineExercise.notes = snapshot.notes
        }

        routine.exercises = originalRoutineExercises.sorted { $0.sortOrder < $1.sortOrder }
        addedRoutineExerciseIDs.removeAll()
        removedRoutineExercises.removeAll()
        structureVersion += 1
    }

    private func commitRoutineChanges(modelContext: ModelContext) {
        let currentIDs = Set(routine.exercises.map(\.id))
        for routineExercise in removedRoutineExercises where !currentIDs.contains(routineExercise.id) {
            modelContext.delete(routineExercise)
        }
        removedRoutineExercises.removeAll()
        addedRoutineExerciseIDs.removeAll()
    }

    // MARK: - Sets

    public func toggleSetCompletion(for routineExerciseID: UUID, setIndex: Int, modelContext: ModelContext) {
        guard var sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }

        let isNowCompleted = !sets[setIndex].isCompleted
        sets[setIndex].isCompleted = isNowCompleted

        if isNowCompleted {
            let targetSet = sets[setIndex]
            let routineExercise = routine.exercises.first(where: { $0.id == routineExerciseID })
            let exercise = routineExercise?.exercise

            let log = WorkoutSetLog(
                date: Date(),
                workoutStartDate: session.startDate,
                weight: targetSet.weight,
                reps: targetSet.reps,
                targetRepsMin: routineExercise?.targetRepsMin ?? 8,
                targetRepsMax: routineExercise?.targetRepsMax ?? 12,
                isCompleted: true,
                routineExerciseID: routineExerciseID,
                setNumber: setIndex + 1,
                exercise: exercise,
                session: session
            )
            modelContext.insert(log)
            session.setsCompleted.append(log)
            sets[setIndex].existingLog = log
            activeSets[routineExerciseID] = sets
            session.totalVolumeKg += (targetSet.weight * Double(targetSet.reps))
            try? modelContext.save()

            if let exercise, let routineExercise {
                let condition: RestCondition
                if case .timer = exercise.defaultRestCondition {
                    condition = .timer(seconds: max(0, routineExercise.restSeconds))
                } else {
                    condition = exercise.defaultRestCondition
                }
                currentExerciseName = exercise.name
                restingSetNumber = setIndex + 1
                restingTotalSets = sets.count
                startRest(with: condition, exerciseName: exercise.name)
            }
        } else {
            let targetSet = sets[setIndex]
            let volumeToSubtract: Double

            if let log = targetSet.existingLog {
                volumeToSubtract = log.weight * Double(log.reps)
                session.setsCompleted.removeAll { $0.id == log.id }
                modelContext.delete(log)
            } else {
                volumeToSubtract = targetSet.weight * Double(targetSet.reps)
            }

            sets[setIndex].existingLog = nil
            activeSets[routineExerciseID] = sets
            session.totalVolumeKg = max(0, session.totalVolumeKg - volumeToSubtract)
            try? modelContext.save()
        }

        refreshLiveActivity()
        persistState()
    }

    public func updateSetValues(
        for routineExerciseID: UUID,
        setIndex: Int,
        weight: Double,
        reps: Int,
        modelContext: ModelContext
    ) {
        guard var sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }

        let sanitizedWeight = max(0, weight)
        let sanitizedReps = max(0, reps)

        guard sets[setIndex].weight != sanitizedWeight || sets[setIndex].reps != sanitizedReps else {
            return
        }

        sets[setIndex].weight = sanitizedWeight
        sets[setIndex].reps = sanitizedReps

        if sets[setIndex].isCompleted, let log = sets[setIndex].existingLog {
            let previousVolume = log.weight * Double(log.reps)
            let newVolume = sanitizedWeight * Double(sanitizedReps)

            log.weight = sanitizedWeight
            log.reps = sanitizedReps
            session.totalVolumeKg = max(0, session.totalVolumeKg - previousVolume + newVolume)
            try? modelContext.save()
        }

        activeSets[routineExerciseID] = sets
        persistState()
    }

    // MARK: - Scene Phase

    public func handleScenePhaseBackground(modelContext: ModelContext) {
        try? modelContext.save()
        LiveActivityManager.shared.handleScenePhaseBackground()

        // Actualizamos el tiempo restante antes de persistir para que el estado
        // guardado refleje el instante exacto en el que la app se va a segundo plano.
        if isResting, !isRestPaused {
            updateRestRemainingFromClock()
        }

        persistState()
    }

    public func handleScenePhaseActive() {
        LiveActivityManager.shared.handleScenePhaseActive()

        guard isResting, !isRestPaused, !isRestFinishing else {
            refreshLiveActivity()
            return
        }

        if isRestTimerActive, let endDate = restTimerEndDate {
            let remaining = endDate.timeIntervalSinceNow
            if remaining > 0 {
                resumeRestRendering(remaining: remaining)
            } else {
                restTimeRemaining = 0
                finishRestOnForeground()
            }
            return
        }

        if let condition = currentRestCondition, case .bpmDrop(let targetBpm) = condition {
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
    }

    // MARK: - Rest Timer & BPM Drop Logic

    private func startRest(with condition: RestCondition, exerciseName: String) {
        stopRest()
        isResting = true
        isRestPaused = false
        isTimerMinimized = false
        currentRestCondition = condition
        currentExerciseName = exerciseName

        switch condition {
        case .timer(let seconds):
            let startDate = Date()
            totalRestSeconds = seconds
            restTimeRemaining = seconds
            timerStartDate = startDate
            timerTargetDuration = seconds
            restTimerEndDate = startDate.addingTimeInterval(Double(seconds))
            isRestTimerActive = true
            currentRestModeTitle = "Descanso (\(seconds)s)"
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            restTargetBpm = targetBpm
            currentRestModeTitle = "Esperando recuperación (< \(targetBpm) BPM)"
            timerStartDate = nil
            timerTargetDuration = 0
            restTimerEndDate = nil
            isRestTimerActive = false
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
        persistState()
    }

    private func startTimerCountdown() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isRestPaused else { return }

                let remaining: TimeInterval
                if let endDate = self.restTimerEndDate {
                    remaining = endDate.timeIntervalSinceNow
                } else if let startDate = self.timerStartDate {
                    remaining = Double(self.timerTargetDuration) - Date().timeIntervalSince(startDate)
                } else {
                    return
                }

                if remaining <= 0 {
                    // Solo mutamos el estado al terminar: la UI descuenta el
                    // tiempo con TimelineView y así evitamos re-renderizar la
                    // vista completa cada segundo.
                    self.restTimeRemaining = 0
                    self.finishRest()
                    return
                }

                // Dormimos en fragmentos cortos para reaccionar a +10/-10 s,
                // pero sin publicar cambios de estado en cada iteración.
                let sleepSeconds = min(remaining, 1.0)
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            }
        }
    }

    private func startBpmRecoveryObserver(targetBpm: Int) {
        bpmObserverTask?.cancel()
        bpmObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isResting, !self.isRestPaused else { return }

                let currentBPM = BPMManager.shared.currentBPM
                if currentBPM > 0, currentBPM <= targetBpm {
                    self.finishRest()
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    public func add10Seconds() {
        guard isResting, let condition = currentRestCondition, case .timer = condition else { return }

        if isRestPaused {
            restTimeRemaining += 10
            totalRestSeconds += 10
            timerTargetDuration = restTimeRemaining
        } else if let startDate = timerStartDate {
            timerTargetDuration += 10
            totalRestSeconds += 10
            restTimerEndDate = startDate.addingTimeInterval(Double(timerTargetDuration))
            isRestTimerActive = true
            updateRestRemainingFromClock()
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
        }

        refreshLiveActivity()
        persistState()
    }

    public func sub10Seconds() {
        guard isResting, let condition = currentRestCondition, case .timer = condition else { return }

        if isRestPaused {
            restTimeRemaining -= 10
            totalRestSeconds = max(10, totalRestSeconds - 10)
            if restTimeRemaining <= 0 {
                finishRest()
            } else {
                timerTargetDuration = restTimeRemaining
            }
        } else if let startDate = timerStartDate {
            let newTarget = timerTargetDuration - 10
            let remaining = Int(ceil(Double(newTarget) - Date().timeIntervalSince(startDate)))

            if remaining <= 0 {
                timerTargetDuration = max(0, newTarget)
                restTimeRemaining = 0
                finishRest()
            } else {
                timerTargetDuration = newTarget
                totalRestSeconds = max(10, totalRestSeconds - 10)
                restTimeRemaining = remaining
                restTimerEndDate = startDate.addingTimeInterval(Double(newTarget))
                isRestTimerActive = true
                if let endDate = restTimerEndDate {
                    NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
                }
            }
        }

        if !isRestFinishing {
            refreshLiveActivity()
        }
        persistState()
    }

    public func pauseRest() {
        guard isResting, !isRestPaused else { return }

        isRestPaused = true
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil
        NotificationManager.shared.cancelRestFinishedNotification()

        if let condition = currentRestCondition, case .timer = condition, timerStartDate != nil {
            updateRestRemainingFromClock()
            timerStartDate = nil
            timerTargetDuration = restTimeRemaining
        }

        restTimerEndDate = nil
        isRestTimerActive = false
        refreshLiveActivity()
        persistState()
    }

    public func resumeRest() {
        guard isResting, isRestPaused, let condition = currentRestCondition else { return }

        isRestPaused = false

        switch condition {
        case .timer:
            guard restTimeRemaining > 0 else {
                finishRest()
                return
            }
            let startDate = Date()
            timerStartDate = startDate
            timerTargetDuration = restTimeRemaining
            restTimerEndDate = startDate.addingTimeInterval(Double(timerTargetDuration))
            isRestTimerActive = true
            if let endDate = restTimerEndDate {
                NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
            }
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }

        refreshLiveActivity()
        persistState()
    }

    private func updateRestRemainingFromClock() {
        if let endDate = restTimerEndDate {
            restTimeRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            return
        }

        guard let startDate = timerStartDate else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        restTimeRemaining = max(0, Int(ceil(Double(timerTargetDuration) - elapsed)))
    }

    public func resumeRestRendering(remaining: TimeInterval) {
        guard isResting, !isRestPaused, restTimerEndDate != nil else { return }
        restTimeRemaining = max(0, Int(ceil(remaining)))
        startTimerCountdown()
        refreshLiveActivity()
    }

    public func finishRestOnForeground() {
        guard isResting, !isRestFinishing else { return }
        restTimeRemaining = 0
        finishRest()
    }

    public func skipRest() {
        guard isResting, !isRestFinishing else { return }
        beginRestDismissal()
    }

    private func finishRest() {
        guard isResting, !isRestFinishing else { return }
        AudioAlertService.shared.playRestFinishedAlert()
        beginRestDismissal()
    }

    private func beginRestDismissal() {
        restDismissalTask?.cancel()
        isRestFinishing = true
        restTimerEndDate = nil
        isRestTimerActive = false
        NotificationManager.shared.cancelRestFinishedNotification()
        refreshLiveActivity()
        persistState()

        restDismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self, !Task.isCancelled, self.isRestFinishing else { return }

            self.clearRestState()
            self.refreshLiveActivity()
        }
    }

    public func stopRest() {
        clearRestState()
    }

    private func clearRestState() {
        NotificationManager.shared.cancelRestFinishedNotification()
        restDismissalTask?.cancel()
        restDismissalTask = nil
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil
        isResting = false
        isRestFinishing = false
        isRestPaused = false
        restTargetBpm = nil
        timerStartDate = nil
        timerTargetDuration = 0
        restTimerEndDate = nil
        isRestTimerActive = false
        currentRestCondition = nil
        persistState()
    }

    // MARK: - Persistencia de la sesión

    /// Guarda en `UserDefaults` el estado completo de la rutina activa para
    /// poder restaurarla tal cual si el usuario cierra la app por completo.
    public func persistState() {
        guard session.endDate == nil else {
            ActiveWorkoutStateStore.clear()
            return
        }

        let completedSets: [PersistedWorkoutSet] = activeSets.flatMap { entry in
            entry.value.compactMap { set in
                guard set.isCompleted else { return nil }
                return PersistedWorkoutSet(
                    routineExerciseID: entry.key,
                    setNumber: set.setNumber,
                    weight: set.weight,
                    reps: set.reps,
                    date: set.existingLog?.date ?? Date()
                )
            }
        }

        let state = PersistedWorkoutState(
            activeWorkoutID: session.id,
            routineID: routine.id,
            workoutStartDate: session.startDate,
            completedSets: completedSets,
            restTimerEndDate: restTimerEndDate,
            bpmHistory: bpmHistory.map {
                PersistedBPMPoint(timestamp: $0.timestamp, bpm: $0.bpm)
            },
            timerStartDate: timerStartDate,
            totalRestSeconds: totalRestSeconds,
            restTimeRemaining: restTimeRemaining,
            isResting: isResting,
            isRestPaused: isRestPaused,
            isRestTimerActive: isRestTimerActive,
            isTimerMinimized: isTimerMinimized,
            restCondition: currentRestCondition,
            restTargetBpm: restTargetBpm,
            currentExerciseName: currentExerciseName,
            currentRestModeTitle: currentRestModeTitle,
            restingSetNumber: restingSetNumber,
            restingTotalSets: restingTotalSets,
            updatedAt: Date()
        )

        ActiveWorkoutStateStore.save(state)
    }

    private func restorePersistedStateIfNeeded(modelContext: ModelContext) {
        guard session.endDate == nil,
              let state = ActiveWorkoutStateStore.load(),
              state.activeWorkoutID == session.id,
              state.routineID == routine.id else { return }

        // Recuperamos siempre el historial de BPM y las series completadas,
        // independientemente de que hubiera un descanso en curso.
        restoreBPMHistory(from: state)
        restoreCompletedSets(from: state.completedSets, modelContext: modelContext)

        guard state.isResting else { return }

        currentExerciseName = state.currentExerciseName
        currentRestModeTitle = state.currentRestModeTitle
        restingSetNumber = state.restingSetNumber
        restingTotalSets = state.restingTotalSets
        totalRestSeconds = state.totalRestSeconds
        isTimerMinimized = state.isTimerMinimized
        restTargetBpm = state.restTargetBpm
        currentRestCondition = state.restCondition

        if currentRestCondition == nil {
            currentRestCondition = .timer(seconds: max(1, state.totalRestSeconds))
        }

        if state.isRestPaused {
            isResting = true
            isRestPaused = true
            restTimeRemaining = max(0, state.restTimeRemaining)
            timerTargetDuration = restTimeRemaining
            timerStartDate = nil
            restTimerEndDate = nil
            isRestTimerActive = false
            return
        }

        if let condition = state.restCondition, case .bpmDrop(let targetBpm) = condition {
            isResting = true
            isRestPaused = false
            restTargetBpm = targetBpm
            timerStartDate = nil
            timerTargetDuration = 0
            restTimerEndDate = nil
            isRestTimerActive = false
            startBpmRecoveryObserver(targetBpm: targetBpm)
            return
        }

        guard state.isRestTimerActive, let endDate = state.restTimerEndDate, endDate > Date() else {
            return
        }

        isResting = true
        isRestPaused = false
        restTimerEndDate = endDate
        timerStartDate = state.timerStartDate ?? Date()
        isRestTimerActive = true
        restTimeRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        timerTargetDuration = max(state.totalRestSeconds, restTimeRemaining)
        NotificationManager.shared.scheduleRestFinishedNotification(endingAt: endDate)
        AudioAlertService.shared.startBackgroundAudio()
        startTimerCountdown()
    }

    /// Restaura las lecturas de pulso guardadas para que la gráfica de Big
    /// Picture no se vacíe al volver a abrir la app. El filtro de 3 minutos se
    /// aplica al dibujar, no al restaurar.
    private func restoreBPMHistory(from state: PersistedWorkoutState) {
        bpmHistory = (state.bpmHistory ?? [])
            .filter { $0.bpm > 0 }
            .map { BPMDataPoint(timestamp: $0.timestamp, bpm: $0.bpm) }
    }

    /// Vuelve a crear en SwiftData las series completadas que falten. Así los
    /// pesos, repeticiones e índice actual están listos antes de renderizar
    /// `ActiveWorkoutView`, incluso si el guardado anterior falló a medias.
    private func restoreCompletedSets(
        from persistedSets: [PersistedWorkoutSet],
        modelContext: ModelContext
    ) {
        guard !persistedSets.isEmpty else { return }

        var didInsertMissingLog = false

        for persisted in persistedSets {
            guard var sets = activeSets[persisted.routineExerciseID],
                  sets.indices.contains(persisted.setNumber - 1) else { continue }

            let index = persisted.setNumber - 1
            let routineExercise = routine.exercises.first { $0.id == persisted.routineExerciseID }

            if sets[index].existingLog != nil {
                sets[index].isCompleted = true
                activeSets[persisted.routineExerciseID] = sets
                continue
            }

            let log = WorkoutSetLog(
                date: persisted.date,
                workoutStartDate: session.startDate,
                weight: persisted.weight,
                reps: persisted.reps,
                targetRepsMin: routineExercise?.targetRepsMin ?? 8,
                targetRepsMax: routineExercise?.targetRepsMax ?? 12,
                isCompleted: true,
                routineExerciseID: persisted.routineExerciseID,
                setNumber: persisted.setNumber,
                exercise: routineExercise?.exercise,
                session: session
            )

            modelContext.insert(log)
            session.setsCompleted.append(log)
            sets[index].existingLog = log
            sets[index].isCompleted = true
            sets[index].weight = persisted.weight
            sets[index].reps = persisted.reps
            activeSets[persisted.routineExerciseID] = sets
            didInsertMissingLog = true
        }

        if didInsertMissingLog {
            session.totalVolumeKg = session.setsCompleted
                .filter { $0.isCompleted }
                .reduce(0) { $0 + $1.weight * Double($1.reps) }
        }

        try? modelContext.save()
    }

    // MARK: - Finish / Cancel

    @discardableResult
    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
        endWorkoutActivity()
        HealthKitManager.shared.stopWorkoutSession()
        HealthKitManager.shared.stopHeartRateQuery()
        session.endDate = Date()
        ActiveWorkoutStateStore.clear()
        try? modelContext.save()
        return session
    }

    @discardableResult
    public func finishWorkoutReplacingRoutine(modelContext: ModelContext) -> WorkoutSession {
        commitRoutineChanges(modelContext: modelContext)
        return finishWorkout(modelContext: modelContext)
    }

    @discardableResult
    public func finishWorkoutHistoryOnly(modelContext: ModelContext) -> WorkoutSession {
        restoreOriginalStructure(modelContext: modelContext)
        return finishWorkout(modelContext: modelContext)
    }

    @discardableResult
    public func finishWorkoutSavingAsNewRoutine(named name: String, modelContext: ModelContext) -> WorkoutSession {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routineName = trimmedName.isEmpty ? "\(routine.name) (modificada)" : trimmedName

        let copiedExercises = routine.exercises
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { routineExercise in
                RoutineExercise(
                    exercise: routineExercise.exercise,
                    defaultSets: routineExercise.defaultSets,
                    targetRepsMin: routineExercise.targetRepsMin,
                    targetRepsMax: routineExercise.targetRepsMax,
                    sortOrder: routineExercise.sortOrder,
                    defaultWeight: routineExercise.defaultWeight,
                    restSeconds: routineExercise.restSeconds,
                    notes: routineExercise.notes
                )
            }

        copiedExercises.forEach { modelContext.insert($0) }
        let newRoutine = Routine(name: routineName, isTemplate: true, exercises: copiedExercises)
        modelContext.insert(newRoutine)
        restoreOriginalStructure(modelContext: modelContext)
        try? modelContext.save()
        return finishWorkout(modelContext: modelContext)
    }

    public func cancelWorkout(modelContext: ModelContext) {
        stopRest()
        endWorkoutActivity()
        HealthKitManager.shared.stopWorkoutSession()
        HealthKitManager.shared.stopHeartRateQuery()
        restoreOriginalStructure(modelContext: modelContext)
        modelContext.delete(session)
        ActiveWorkoutStateStore.clear()
        try? modelContext.save()
    }

    // MARK: - Live Activity

    private func makeLiveActivitySnapshot() -> LiveActivityManager.Snapshot {
        let info = currentExerciseInfo()
        let endDate = isRestTimerActive ? restTimerEndDate : nil
        let isActive = isRestTimerActive && endDate != nil

        return LiveActivityManager.Snapshot(
            exerciseName: info.name,
            currentSet: info.currentSet,
            totalSets: info.totalSets,
            timerStartDate: isActive ? timerStartDate : nil,
            timerEndDate: endDate,
            isRestTimerActive: isActive
        )
    }

    public func startWorkoutActivityIfNeeded() {
        guard session.endDate == nil, !didStartWorkoutActivity else { return }
        didStartWorkoutActivity = true
        NotificationManager.shared.requestAuthorization()
        HealthKitManager.shared.startWorkoutSession()
        AudioAlertService.shared.startBackgroundAudio()

        LiveActivityManager.shared.startActivity(
            workoutName: routine.name,
            snapshot: makeLiveActivitySnapshot(),
            bpm: HealthKitManager.shared.currentBPM
        )
    }

    private func refreshLiveActivity() {
        guard didStartWorkoutActivity, session.endDate == nil else { return }
        LiveActivityManager.shared.updateSnapshot(makeLiveActivitySnapshot())
    }

    private func endWorkoutActivity() {
        didStartWorkoutActivity = false
        NotificationManager.shared.cancelRestFinishedNotification()
        AudioAlertService.shared.stopBackgroundAudio()
        LiveActivityManager.shared.endActivity()
        ActiveWorkoutStateStore.clear()
    }

    private func currentExerciseInfo() -> (name: String, currentSet: Int, totalSets: Int) {
        if isResting, !currentExerciseName.isEmpty, restingTotalSets > 0 {
            return (currentExerciseName, restingSetNumber, restingTotalSets)
        }

        let exercises = routine.exercises.sorted { $0.sortOrder < $1.sortOrder }

        for routineExercise in exercises {
            guard let sets = activeSets[routineExercise.id], !sets.isEmpty else { continue }

            if let nextSetIndex = sets.firstIndex(where: { !$0.isCompleted }) {
                return (
                    routineExercise.exercise?.name ?? "Ejercicio",
                    nextSetIndex + 1,
                    sets.count
                )
            }
        }

        if let lastExercise = exercises.last,
           let sets = activeSets[lastExercise.id],
           !sets.isEmpty {
            return (
                lastExercise.exercise?.name ?? "Ejercicio",
                sets.count,
                sets.count
            )
        }

        return (routine.name, 0, 0)
    }

    // MARK: - Big Picture Mode

    private var bigPictureSortedExercises: [RoutineExercise] {
        routine.exercises.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var bigPictureCurrentRoutineExercise: RoutineExercise? {
        bigPictureSortedExercises.first { routineExercise in
            guard let sets = activeSets[routineExercise.id] else { return false }
            return sets.contains { !$0.isCompleted }
        } ?? bigPictureSortedExercises.first
    }

    public var bigPictureCurrentExercise: String {
        guard let exercise = bigPictureCurrentRoutineExercise?.exercise else { return "—" }
        return exercise.name
    }

    public var bigPictureNextExercise: String {
        let sorted = bigPictureSortedExercises
        guard let current = bigPictureCurrentRoutineExercise,
              let currentIndex = sorted.firstIndex(where: { $0.id == current.id }),
              currentIndex + 1 < sorted.count,
              let nextExercise = sorted[currentIndex + 1].exercise else { return "" }
        return "SIG: \(nextExercise.name)"
    }

    public var bigPictureCurrentExerciseID: UUID? {
        bigPictureCurrentRoutineExercise?.id
    }

    public var bigPictureCurrentWeight: Double {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let pending = sets.first(where: { !$0.isCompleted }) else { return 0 }
        return pending.weight
    }

    public var bigPictureCurrentReps: Int {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let pending = sets.first(where: { !$0.isCompleted }) else { return 0 }
        return pending.reps
    }

    public var bigPictureSetsForCurrentExercise: [WorkoutSetLog] {
        guard let exercise = bigPictureCurrentRoutineExercise?.exercise else { return [] }
        return session.setsCompleted
            .filter { $0.exercise?.id == exercise.id && $0.isCompleted }
            .sorted { $0.date < $1.date }
    }

    /// Filas de la parrilla de series del ejercicio actual en Big Picture.
    /// Columna 1: número de serie. Columna 2: marca de la última sesión previa ("kg · reps" o "-").
    /// Columna 3: marca de la sesión actual si ya se completó (verde), o vacía si aún no.
    public struct BigPictureSetRow: Identifiable {
        public let id = UUID()
        public let setNumber: Int
        public let previousText: String?
        public let currentText: String?
    }

    public func bigPictureSetRows(modelContext: ModelContext) -> [BigPictureSetRow] {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let exercise = bigPictureCurrentRoutineExercise?.exercise else { return [] }

        let currentSets = sets.sorted { $0.setNumber < $1.setNumber }

        // Última sesión previa para este ejercicio (excluyendo la sesión en curso).
        let sessionID = session.id
        let descriptor = FetchDescriptor<WorkoutSetLog>(
            predicate: #Predicate { (log: WorkoutSetLog) -> Bool in
                return log.exercise?.id == exercise.id && log.isCompleted && log.session?.id != sessionID
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let pastLogs = (try? modelContext.fetch(descriptor)) ?? []

        // Agrupar por sesión y quedarse con la más reciente.
        // `pastLogs` viene ordenado por fecha descendente, así que el primer
        // log pertenece a la última sesión previa.
        let latestSessionID: UUID? = pastLogs.first?.session?.id
        let latestSessionLogs: [WorkoutSetLog]
        if let latestSessionID {
            let groupedLogs: [UUID?: [WorkoutSetLog]] = Dictionary(grouping: pastLogs) { (log: WorkoutSetLog) -> UUID? in
                return log.session?.id
            }
            if let logs = groupedLogs[latestSessionID] {
                latestSessionLogs = logs.sorted { (lhs: WorkoutSetLog, rhs: WorkoutSetLog) -> Bool in
                    return (lhs.setNumber ?? 0) < (rhs.setNumber ?? 0)
                }
            } else {
                latestSessionLogs = []
            }
        } else {
            latestSessionLogs = []
        }

        var rows: [BigPictureSetRow] = []
        for set in currentSets {
            let previous = latestSessionLogs.first { $0.setNumber == set.setNumber }
            let previousText = previous.map { "\(Int($0.weight)) kg · \($0.reps)" }

            let currentText: String?
            if set.isCompleted, let log = set.existingLog {
                currentText = "\(Int(log.weight)) kg · \(log.reps)"
            } else {
                currentText = nil
            }

            rows.append(BigPictureSetRow(
                setNumber: set.setNumber,
                previousText: previousText,
                currentText: currentText
            ))
        }

        return rows
    }

    public var bigPictureIsTimerShowing: Bool {
        isResting && hasActiveRestTimer
    }

    public var bigPictureRemainingTime: Int {
        guard let endDate = restTimerEndDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    public var bigPictureRemainingTimeFormatted: String {
        let seconds = bigPictureRemainingTime
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    public var bigPictureRestProgress: Double {
        guard totalRestSeconds > 0 else { return 0 }
        return max(0, min(1, Double(bigPictureRemainingTime) / Double(totalRestSeconds)))
    }

    public func bigPictureUpdateWeight(_ weight: Double, modelContext: ModelContext) {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let index = sets.firstIndex(where: { !$0.isCompleted }) else { return }

        updateSetValues(
            for: id,
            setIndex: index,
            weight: weight,
            reps: sets[index].reps,
            modelContext: modelContext
        )
    }

    public func bigPictureAdjustReps(_ delta: Int) {
        guard let id = bigPictureCurrentExerciseID,
              var sets = activeSets[id],
              let index = sets.firstIndex(where: { !$0.isCompleted }) else { return }
        sets[index].reps = max(0, sets[index].reps + delta)
        activeSets[id] = sets
    }

    public func bigPictureRegisterSet(modelContext: ModelContext) {
        guard let id = bigPictureCurrentExerciseID,
              let sets = activeSets[id],
              let setIndex = sets.firstIndex(where: { !$0.isCompleted }) else { return }
        toggleSetCompletion(for: id, setIndex: setIndex, modelContext: modelContext)
    }

    // MARK: - BPM History (Big Picture chart)

    public struct BPMDataPoint: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let bpm: Int
    }

    public var bpmHistory: [BPMDataPoint] = []
    private let bpmHistoryWindow: TimeInterval = 180
    private var lastBPMPersistDate: Date = .distantPast

    /// Historial de BPM filtrado a los últimos 3 minutos respecto al instante actual.
    /// Tipos de retorno explícitos para evitar fallos de inferencia en el chart.
    public var bpmHistoryLast3Minutes: [BPMDataPoint] {
        let now: Date = Date()
        let threeMinutesAgo: Date = now.addingTimeInterval(-180.0)
        return bpmHistory.filter { (sample: BPMDataPoint) -> Bool in
            return sample.timestamp >= threeMinutesAgo
        }
    }

    public func addBPMPoint(_ bpm: Int) {
        guard bpm > 0 else { return }

        let now = Date()
        bpmHistory.append(BPMDataPoint(timestamp: now, bpm: bpm))
        pruneBPMHistory(relativeTo: now)
        persistBPMHistoryIfNeeded(now: now)
    }

    /// Lecturas dentro de la ventana indicada respecto a `date`. La vista la
    /// evalúa dentro de un `TimelineView`, por lo que la ventana de 3 minutos
    /// se desplaza sola aunque no lleguen nuevas lecturas.
    public func bpmPoints(
        within window: TimeInterval = 180,
        relativeTo date: Date = Date()
    ) -> [BPMDataPoint] {
        let cutoff = date.addingTimeInterval(-window)
        return bpmHistory.filter { $0.timestamp >= cutoff && $0.timestamp <= date }
    }

    private func pruneBPMHistory(relativeTo date: Date) {
        let cutoff = date.addingTimeInterval(-(bpmHistoryWindow + 5))
        guard let firstValid = bpmHistory.firstIndex(where: { $0.timestamp >= cutoff }),
              firstValid > 0 else { return }
        bpmHistory.removeFirst(firstValid)
    }

    private func persistBPMHistoryIfNeeded(now: Date) {
        guard session.endDate == nil else { return }
        guard now.timeIntervalSince(lastBPMPersistDate) >= 10 else { return }
        lastBPMPersistDate = now
        persistState()
    }

    public func clearBPMHistory() {
        bpmHistory.removeAll()
    }
}
