import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?
    public var totalVolumeKg: Double

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.session)
    public var setsCompleted: [WorkoutSetLog] = []

    public init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        totalVolumeKg: Double = 0.0,
        setsCompleted: [WorkoutSetLog] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalVolumeKg = totalVolumeKg
        self.setsCompleted = setsCompleted
    }
}

@Model
public final class WorkoutSetLog {
    public var id: UUID
    public var date: Date
    public var weight: Double
    public var reps: Int
    public var isCompleted: Bool
    public var routineExerciseID: UUID?
    public var setNumber: Int?

    public var exercise: Exercise?
    public var session: WorkoutSession?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        weight: Double = 0.0,
        reps: Int = 0,
        isCompleted: Bool = false,
        routineExerciseID: UUID? = nil,
        setNumber: Int? = nil,
        exercise: Exercise? = nil,
        session: WorkoutSession? = nil
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.routineExerciseID = routineExerciseID
        self.setNumber = setNumber
        self.exercise = exercise
        self.session = session
    }
}
