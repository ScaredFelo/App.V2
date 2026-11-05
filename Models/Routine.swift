import Foundation
import SwiftData

@Model
public final class Routine {
    public var id: UUID
    public var name: String
    public var isTemplate: Bool
    public var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade)
    public var exercises: [RoutineExercise] = []

    public init(
        id: UUID = UUID(),
        name: String,
        isTemplate: Bool = true,
        sortOrder: Int = 0,
        exercises: [RoutineExercise] = []
    ) {
        self.id = id
        self.name = name
        self.isTemplate = isTemplate
        self.sortOrder = sortOrder
        self.exercises = exercises
    }
}

@Model
public final class RoutineExercise {
    public var id: UUID
    public var defaultSets: Int
    public var targetRepsMin: Int = 8
    public var targetRepsMax: Int = 12
    public var sortOrder: Int
    public var defaultWeight: Double = 0.0
    public var restSeconds: Int = 90
    public var notes: String = ""

    @Relationship
    public var exercise: Exercise?

    @Transient
    public var targetRepsText: String {
        "\(targetRepsMin) - \(targetRepsMax)"
    }

    public init(
        id: UUID = UUID(),
        exercise: Exercise?,
        defaultSets: Int = 3,
        targetRepsMin: Int = 8,
        targetRepsMax: Int = 12,
        sortOrder: Int = 0,
        defaultWeight: Double = 0.0,
        restSeconds: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.exercise = exercise
        self.defaultSets = defaultSets
        let lower = max(1, min(targetRepsMin, targetRepsMax))
        self.targetRepsMin = lower
        self.targetRepsMax = max(lower, targetRepsMax)
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
