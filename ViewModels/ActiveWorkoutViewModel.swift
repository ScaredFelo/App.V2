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
        let targetReps: Int
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
            predicate: #Predicate { $0.exercise?.id == exerciseID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        let pastLogs = (try? modelContext.fetch(descriptor)) ?? []
        let currentLogs = session.setsCompleted.filter {
            $0.exercise?.id == exerciseID && $0.isCompleted
        }
        var legacyLogs = currentLogs
            .filter { $0.routineExerciseID == nil }
            .sorted { $0.date < $1.date }
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

            let matchingLog = pastLogs.indices.contains(i - 1) ? pastLogs[i - 1] : pastLogs.first
            let ghostW = matchingLog?.weight
            let ghostR = matchingLog?.reps
            let initialWeight = routineExercise.defaultWeight > 0 ? routineExercise.defaultWeight : (ghostW ?? 0.0)
            let initialReps = routineExercise.targetReps

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
        let routineExercise = RoutineExercise(exercise: exercise, sortOrder: nextOrder)

        modelContext.insert(routineExercise)
        routine.exercises.append(routineExercise)
        activeSets[routineExercise.id] = buildSetStates(for: routineExercise, modelContext: modelContext)
        addedRoutineExerciseIDs.insert(routineExercise.id)
        structureVersion += 1
        try? modelContext.save()

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
                targetReps: $0.targetReps,
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
                routineExercise.targetReps != snapshot.targetReps ||
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
            routineExercise.targetReps = snapshot.targetReps
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
                weight: targetSet.weight,
                reps: targetSet.reps,
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
    }

    private func startTimerCountdown() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isRestPaused else { return }

                let remaining: Int
                if let endDate = self.restTimerEndDate {
                    remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
                } else if let startDate = self.timerStartDate {
                    let elapsed = Date().timeIntervalSince(startDate)
                    remaining = max(0, Int(ceil(Double(self.timerTargetDuration) - elapsed)))
                } else {
                    return
                }

                self.restTimeRemaining = remaining

                if remaining <= 0 {
                    self.finishRest()
                    return
                }

                try? await Task.sleep(nanoseconds: 500_000_000)
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
    }

    // MARK: - Finish / Cancel

    @discardableResult
    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
        endWorkoutActivity()
        HealthKitManager.shared.stopHeartRateQuery()
        session.endDate = Date()
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
                    targetReps: routineExercise.targetReps,
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
        HealthKitManager.shared.stopHeartRateQuery()
        restoreOriginalStructure(modelContext: modelContext)
        modelContext.delete(session)
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
}
