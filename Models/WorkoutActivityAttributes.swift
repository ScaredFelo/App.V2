import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var timerEndDate: Date
        public var totalDuration: Int
        public var sessionStartDate: Date
        public var currentBPM: Int
        public var exerciseName: String
        public var currentSet: Int

        public var timerStartDate: Date {
            timerEndDate.addingTimeInterval(-Double(max(0, totalDuration)))
        }

        public init(
            timerEndDate: Date,
            totalDuration: Int,
            sessionStartDate: Date,
            currentBPM: Int,
            exerciseName: String,
            currentSet: Int
        ) {
            self.timerEndDate = timerEndDate
            self.totalDuration = totalDuration
            self.sessionStartDate = sessionStartDate
            self.currentBPM = currentBPM
            self.exerciseName = exerciseName
            self.currentSet = currentSet
        }
    }
    
    public var workoutName: String

    public init(workoutName: String) {
        self.workoutName = workoutName
    }
}
