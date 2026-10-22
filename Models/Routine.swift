import Foundation
import SwiftData

@Model
public final class Routine {
    public var id: UUID
    public var name: String
    public var isTemplate: Bool

    @Relationship(deleteRule: .cascade)
    public var exercises: [RoutineExercise] = []

    public init(
        id: UUID = UUID(),
        name: String,
        isTemplate: Bool = true,
        exercises: [RoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.isTemplate = isTemplate
        self.exercises = exercises
    }
}

@Model
public final class RoutineExercise {
    public var id: UUID
    public var defaultSets: Int
    public var targetReps: Int
    public var sortOrder: Int
    public var defaultWeight: Double = 0.0
    public var restSeconds: Int = 90
    public var notes: String = ""

    @Relationship
    public var exercise: Exercise?

    public init(
        id: UUID = UUID(),
        exercise: Exercise?,
        defaultSets: Int = 3,
        targetReps: Int = 10,
        sortOrder: Int = 0,
        defaultWeight: Double = 0.0,
        restSeconds: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.exercise = exercise
        self.defaultSets = defaultSets
        self.targetReps = targetReps
        self.sortOrder = sortOrder
        self.defaultWeight = defaultWeight
        self.notes = notes

        if let restSeconds {
            self.restSeconds = restSeconds
        } else if let exercise, case let .timer(seconds) = exercise.defaultRestCondition {
            self.restSeconds = seconds
        } else {
            self.restSeconds = 90
        }
    }
}
