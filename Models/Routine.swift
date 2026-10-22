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

    @Relationship
    public var exercise: Exercise?

    public init(
        id: UUID = UUID(),
        exercise: Exercise?,
        defaultSets: Int = 3,
        targetReps: Int = 10,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.exercise = exercise
        self.defaultSets = defaultSets
        self.targetReps = targetReps
        self.sortOrder = sortOrder
    }
}
