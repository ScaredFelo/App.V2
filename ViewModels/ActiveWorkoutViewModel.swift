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
    
    // Rest Timer State
    public var isResting = false
    public var restTimeRemaining = 0
    public var totalRestSeconds = 0
    public var restTargetBpm: Int?
    public var currentRestModeTitle = ""
    public var currentExerciseName = ""
    public var timerEndDate: Date?
    public var isTimerMinimized: Bool = false
    
    private var timerTask: Task<Void, Never>?
    private var bpmObserverTask: Task<Void, Never>?
    private var currentActivity: Activity<WorkoutActivityAttributes>?
    private var cancellables = Set<AnyCancellable>()

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
        setupBPMObserver()
    }

    private func setupInitialSets(modelContext: ModelContext) {
        for routineExercise in routine.exercises {
            guard let exercise = routineExercise.exercise else { continue }
            var sets: [SetInputState] = []
            
            let exerciseID = exercise.id
            let descriptor = FetchDescriptor<WorkoutSetLog>(
                predicate: #Predicate { $0.exercise?.id == exerciseID },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            let pastLogs = (try? modelContext.fetch(descriptor)) ?? []
            
            for i in 1...routineExercise.defaultSets {
                let matchingLog = pastLogs.indices.contains(i - 1) ? pastLogs[i - 1] : pastLogs.first
                let ghostW = matchingLog?.weight
                let ghostR = matchingLog?.reps
                
                sets.append(SetInputState(
                    setNumber: i,
                    weight: ghostW ?? 0.0,
                    reps: routineExercise.targetReps,
                    isCompleted: false,
                    ghostWeight: ghostW,
                    ghostReps: ghostR
                ))
            }
            activeSets[routineExercise.id] = sets
        }
    }

    public func toggleSetCompletion(for routineExerciseID: UUID, setIndex: Int, modelContext: ModelContext) {
        guard var sets = activeSets[routineExerciseID], sets.indices.contains(setIndex) else { return }
        sets[setIndex].isCompleted.toggle()
        activeSets[routineExerciseID] = sets
        
        if sets[setIndex].isCompleted {
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
            session.totalVolumeKg += (targetSet.weight * Double(targetSet.reps))
            try? modelContext.save()
            
            if let restCondition = exercise?.defaultRestCondition, let exerciseName = exercise?.name {
                currentExerciseName = exerciseName
                startRest(with: restCondition, exerciseName: exerciseName)
            }
        }
    }

    // MARK: - Rest Timer & BPM Drop Logic
    private func startRest(with condition: RestCondition, exerciseName: String) {
        stopRest()
        isResting = true
        
        let duration: Int
        if case let .timer(seconds) = condition {
            duration = seconds
        } else {
            duration = 0
        }
        
        timerEndDate = Date().addingTimeInterval(Double(duration))
        startLiveActivity(exerciseName: exerciseName, restCondition: condition, timerEndDate: timerEndDate!)

        switch condition {
        case .timer(let seconds):
            totalRestSeconds = seconds
            restTimeRemaining = seconds
            currentRestModeTitle = "Descanso (\(seconds)s)"
            
            timerTask = Task {
                while let endDate = timerEndDate {
                    let remaining = Int(endDate.timeIntervalSinceNow)
                    restTimeRemaining = max(0, remaining)
                    updateLiveActivity()
                    
                    if restTimeRemaining <= 0 {
                        finishRest()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                }
            }

        case .bpmDrop(let targetBpm):
            restTargetBpm = targetBpm
            currentRestModeTitle = "Esperando recuperación (< \(targetBpm) BPM)"
            
            bpmObserverTask = Task {
                while isResting {
                    updateLiveActivity()
                    let currentBPM = BPMManager.shared.currentBPM
                    if currentBPM > 0, currentBPM <= targetBpm {
                        finishRest()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                }
            }
        }
    }

    public func add10Seconds() {
        guard let endDate = timerEndDate else { return }
        let newEndDate = endDate.addingTimeInterval(10)
        timerEndDate = newEndDate
        totalRestSeconds += 10
        restTimeRemaining = Int(newEndDate.timeIntervalSinceNow)
        updateLiveActivity()
    }

    public func sub10Seconds() {
        guard let endDate = timerEndDate else { return }
        let newEndDate = endDate.addingTimeInterval(-10)
        let remaining = Int(newEndDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finishRest()
        } else {
            timerEndDate = newEndDate
            totalRestSeconds = max(10, totalRestSeconds - 10)
            restTimeRemaining = remaining
            updateLiveActivity()
        }
    }

    public func skipRest() {
        finishRest()
    }

    private func finishRest() {
        stopRest()
        AudioAlertService.shared.playRestFinishedAlert()
    }

    public func stopRest() {
        timerTask?.cancel()
        timerTask = nil
        bpmObserverTask?.cancel()
        bpmObserverTask = nil
        isResting = false
        restTargetBpm = nil
        timerEndDate = nil
        endLiveActivity()
    }

    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
        session.endDate = Date()
        try? modelContext.save()
        return session
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
    private func startLiveActivity(exerciseName: String, restCondition: RestCondition, timerEndDate: Date) {
        // Finalizar actividades previas antes de iniciar una nueva
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let currentSetIndex = session.setsCompleted.count
        
        let attributes = WorkoutActivityAttributes(workoutName: routine.name)
        
        let state = WorkoutActivityAttributes.ContentState(
            timerEndDate: timerEndDate,
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
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first, let endDate = timerEndDate else { return }
        
        let currentSetIndex = session.setsCompleted.count
        
        let state = WorkoutActivityAttributes.ContentState(
            timerEndDate: endDate,
            sessionStartDate: session.startDate,
            currentBPM: bpm,
            exerciseName: currentExerciseName,
            currentSet: currentSetIndex + 1
        )
        
        Task {
            await activity.update(ActivityContent(state: state, staleDate: endDate))
        }
    }

    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        let finalState = activity.content.state
        Task {
            await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }
}
