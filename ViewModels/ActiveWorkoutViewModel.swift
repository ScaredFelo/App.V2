import Foundation
import SwiftData
import SwiftUI
import Combine
import ActivityKit

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
    public var restTargetBpm: Int?
    public var currentRestModeTitle = ""
    public var currentExerciseName = ""
    public var timerEndDate: Date?
    public var isTimerMinimized: Bool = false
    public var isRestFinishing: Bool = false

    private var timerTask: Task<Void, Never>?
    private var bpmObserverTask: Task<Void, Never>?
    private var restDismissalTask: Task<Void, Never>?
    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()
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
        setupBPMObserver()
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
        var sets: [SetInputState] = []

        for i in 1...max(1, routineExercise.defaultSets) {
            let matchingLog = pastLogs.indices.contains(i - 1) ? pastLogs[i - 1] : pastLogs.first
            let ghostW = matchingLog?.weight
            let ghostR = matchingLog?.reps
            let initialWeight = routineExercise.defaultWeight > 0 ? routineExercise.defaultWeight : (ghostW ?? 0.0)
            let initialReps = routineExercise.targetReps

            sets.append(SetInputState(
                setNumber: i,
                weight: initialWeight,
                reps: initialReps,
                isCompleted: false,
                ghostWeight: ghostW,
                ghostReps: ghostR
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
            totalRestSeconds = seconds
            restTimeRemaining = seconds
            currentRestModeTitle = "Descanso (\(seconds)s)"
            timerEndDate = Date().addingTimeInterval(Double(seconds))
            startLiveActivity(exerciseName: exerciseName, timerEndDate: timerEndDate!, totalDuration: seconds)
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            restTargetBpm = targetBpm
            currentRestModeTitle = "Esperando recuperación (< \(targetBpm) BPM)"
            timerEndDate = Date()
            startLiveActivity(exerciseName: exerciseName, timerEndDate: timerEndDate!, totalDuration: 0)
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }
    }

    private func startTimerCountdown() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isRestPaused, let endDate = self.timerEndDate else { return }
                let remaining = Int(ceil(endDate.timeIntervalSinceNow))
                self.restTimeRemaining = max(0, remaining)
                self.updateLiveActivity()

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
                self.updateLiveActivity()

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
            timerEndDate = Date().addingTimeInterval(Double(restTimeRemaining))
        } else if let endDate = timerEndDate {
            let newEndDate = endDate.addingTimeInterval(10)
            timerEndDate = newEndDate
            totalRestSeconds += 10
            restTimeRemaining = max(0, Int(ceil(newEndDate.timeIntervalSinceNow)))
            updateLiveActivity()
        }
    }

    public func sub10Seconds() {
        guard isResting, let condition = currentRestCondition, case .timer = condition else { return }

        if isRestPaused {
            restTimeRemaining -= 10
            totalRestSeconds = max(10, totalRestSeconds - 10)
            if restTimeRemaining <= 0 {
                finishRest()
            } else {
                timerEndDate = Date().addingTimeInterval(Double(restTimeRemaining))
            }
        } else if let endDate = timerEndDate {
            let newEndDate = endDate.addingTimeInterval(-10)
            let remaining = Int(ceil(newEndDate.timeIntervalSinceNow))

            if remaining <= 0 {
                finishRest()
            } else {
                timerEndDate = newEndDate
                totalRestSeconds = max(10, totalRestSeconds - 10)
                restTimeRemaining = remaining
                updateLiveActivity()
            }
        }
    }

    public func pauseRest() {
        guard isResting, !isRestPaused else { return }

        isRestPaused = true
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil

        if let condition = currentRestCondition, case .timer = condition, let endDate = timerEndDate {
            restTimeRemaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            timerEndDate = Date().addingTimeInterval(Double(restTimeRemaining))
        }

        endLiveActivity()
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
            timerEndDate = Date().addingTimeInterval(Double(restTimeRemaining))
            startLiveActivity(exerciseName: currentExerciseName, timerEndDate: timerEndDate!, totalDuration: totalRestSeconds)
            AudioAlertService.shared.startBackgroundAudio()
            startTimerCountdown()

        case .bpmDrop(let targetBpm):
            timerEndDate = Date()
            startLiveActivity(exerciseName: currentExerciseName, timerEndDate: timerEndDate!, totalDuration: 0)
            startBpmRecoveryObserver(targetBpm: targetBpm)
        }
    }

    public func skipRest() {
        guard isResting, !isRestFinishing else { return }
        beginRestDismissal(endActivityWhenFinished: false)
    }

    private func finishRest() {
        guard isResting, !isRestFinishing else { return }
        AudioAlertService.shared.playRestFinishedAlert()
        beginRestDismissal(endActivityWhenFinished: true)
    }

    private func beginRestDismissal(endActivityWhenFinished: Bool) {
        restDismissalTask?.cancel()
        isRestFinishing = true

        if !endActivityWhenFinished {
            endLiveActivity()
        }

        restDismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard let self, !Task.isCancelled, self.isRestFinishing else { return }

            self.clearRestState()
            if endActivityWhenFinished {
                self.endLiveActivity(finished: true)
            }
        }
    }

    public func stopRest() {
        clearRestState()
        endLiveActivity()
    }

    private func clearRestState() {
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
        timerEndDate = nil
        currentRestCondition = nil
    }

    // MARK: - Finish / Cancel

    @discardableResult
    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
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
        restoreOriginalStructure(modelContext: modelContext)
        modelContext.delete(session)
        try? modelContext.save()
    }

    // MARK: - BPM Observer
    private func setupBPMObserver() {
        BPMManager.shared.$currentBPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBPM in
                guard let self, newBPM > 0 else { return }
                Task { @MainActor in
                    self.updateLiveActivity(bpm: newBPM)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - ActivityKit (Live Activities / Dynamic Island)
    private func startLiveActivity(exerciseName: String, timerEndDate: Date, totalDuration: Int) {
        // Finalizar actividades previas antes de iniciar una nueva
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let currentSetIndex = session.setsCompleted.count
        let attributes = WorkoutActivityAttributes(workoutName: routine.name)

        let state = WorkoutActivityAttributes.ContentState(
            timerEndDate: timerEndDate,
            totalDuration: totalDuration,
            sessionStartDate: session.startDate,
            currentBPM: BPMManager.shared.currentBPM,
            exerciseName: exerciseName,
            currentSet: currentSetIndex + 1
        )

        let content = ActivityContent(state: state, staleDate: timerEndDate)

        do {
            currentActivity = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("Live Activity iniciada con éxito")
        } catch {
            print("Error iniciando Live Activity: \(error.localizedDescription)")
        }
    }

    private func updateLiveActivity() {
        updateLiveActivity(bpm: BPMManager.shared.currentBPM)
    }

    private func updateLiveActivity(bpm: Int) {
        guard isResting, !isRestPaused,
              let activity = Activity<WorkoutActivityAttributes>.activities.first,
              let endDate = timerEndDate else { return }

        let currentSetIndex = session.setsCompleted.count

        let state = WorkoutActivityAttributes.ContentState(
            timerEndDate: endDate,
            totalDuration: totalRestSeconds,
            sessionStartDate: session.startDate,
            currentBPM: bpm,
            exerciseName: currentExerciseName,
            currentSet: currentSetIndex + 1
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: endDate))
        }
    }

    private func endLiveActivity(finished: Bool = false) {
        guard let activity = currentActivity else {
            AudioAlertService.shared.stopBackgroundAudio()
            return
        }
        currentActivity = nil

        guard finished else {
            AudioAlertService.shared.stopBackgroundAudio()
            let finalState = activity.content.state
            Task {
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            }
            return
        }

        let previousState = activity.content.state
        let finalState = WorkoutActivityAttributes.ContentState(
            timerEndDate: Date(),
            totalDuration: max(0, totalRestSeconds),
            sessionStartDate: previousState.sessionStartDate,
            currentBPM: BPMManager.shared.currentBPM,
            exerciseName: previousState.exerciseName,
            currentSet: previousState.currentSet,
            isRestFinished: true
        )

        Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
            AudioAlertService.shared.stopBackgroundAudio()
        }
    }
}
