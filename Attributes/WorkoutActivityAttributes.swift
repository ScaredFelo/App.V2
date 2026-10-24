import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var exerciseName: String
        public var currentSet: Int
        public var totalSets: Int
        public var timerStartDate: Date?
        public var timerEndDate: Date?
        public var isRestTimerActive: Bool
        public var currentBPM: Int

        public init(
            exerciseName: String,
            currentSet: Int,
            totalSets: Int,
            timerStartDate: Date?,
            timerEndDate: Date?,
            isRestTimerActive: Bool,
            currentBPM: Int
        ) {
            self.exerciseName = exerciseName
            self.currentSet = currentSet
            self.totalSets = totalSets
            self.timerStartDate = timerStartDate
            self.timerEndDate = timerEndDate
            self.isRestTimerActive = isRestTimerActive
            self.currentBPM = currentBPM
        }
    }

    public var workoutName: String

    public init(workoutName: String) {
        self.workoutName = workoutName
    }
}
