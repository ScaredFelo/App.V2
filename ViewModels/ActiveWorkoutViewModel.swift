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
    public var activeSets: [UUID: [SetInputState]] = [:] // RoutineExercise.id -> sets
    
    // Rest Timer State
    public var isResting = false
    public var restTimeRemaining = 0
    public var totalRestSeconds = 0
    public var restTargetBpm: Int?
    public var currentRestModeTitle = ""
    public var currentExerciseName = ""
    
    private var timerTask: Task<Void, Never>?
    private var bpmObserverTask: Task<Void, Never>?
    private var currentActivity: Activity<WorkoutActivityAttributes>?

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
        startLiveActivity(exerciseName: exerciseName, restCondition: condition)

        switch condition {
        case .timer(let seconds):
            totalRestSeconds = seconds
            restTimeRemaining = seconds
            currentRestModeTitle = "Descanso (\(seconds)s)"
            
            timerTask = Task {
                while restTimeRemaining > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                    restTimeRemaining -= 1
                    updateLiveActivity()
                }
                if restTimeRemaining <= 0 {
                    finishRest()
                }
            }

        case .bpmDrop(let targetBpm):
            restTargetBpm = targetBpm
            currentRestModeTitle = "Esperando recuperación (< \(targetBpm) BPM)"
            
            bpmObserverTask = Task {
                while isResting {
                    updateLiveActivity()
                    if let currentBPM = BPMManager.shared.currentBPM, currentBPM <= targetBpm {
                        finishRest()
                        break
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                }
            }
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
        endLiveActivity()
    }

    public func finishWorkout(modelContext: ModelContext) -> WorkoutSession {
        stopRest()
        session.endDate = Date()
        try? modelContext.save()
        return session
    }

    // MARK: - ActivityKit (Live Activities / Dynamic Island)
    private func startLiveActivity(exerciseName: String, restCondition: RestCondition) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let isBpm: Bool
        let targetBpm: Int
        let initialSecs: Int
        
        switch restCondition {
        case .timer(let seconds):
            isBpm = false
            targetBpm = 0
            initialSecs = seconds
        case .bpmDrop(let bpm):
            isBpm = true
            targetBpm = bpm
            initialSecs = 0
        }
        
        let attributes = WorkoutActivityAttributes(routineName: routine.name)
        let initialContentState = WorkoutActivityAttributes.ContentState(
            remainingSeconds: initialSecs,
            currentBPM: BPMManager.shared.currentBPM ?? 0,
            targetBPM: targetBpm,
            exerciseName: exerciseName,
            isBpmMode: isBpm
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContentState, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = currentActivity else { return }
        let isBpm = restTargetBpm != nil
        let target = restTargetBpm ?? 0
        
        let state = WorkoutActivityAttributes.ContentState(
            remainingSeconds: restTimeRemaining,
            currentBPM: BPMManager.shared.currentBPM ?? 0,
            targetBPM: target,
            exerciseName: currentExerciseName,
            isBpmMode: isBpm
        )
        
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
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
