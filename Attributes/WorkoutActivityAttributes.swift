import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var exerciseName: String
        public var currentSet: Int
        public var totalSets: Int
        public var timerText: String
        public var currentBPM: Int

        public init(
            exerciseName: String,
            currentSet: Int,
            totalSets: Int,
            timerText: String,
            currentBPM: Int
        ) {
            self.exerciseName = exerciseName
            self.currentSet = currentSet
            self.totalSets = totalSets
            self.timerText = timerText
            self.currentBPM = currentBPM
        }
    }

    public var workoutName: String

    public init(workoutName: String) {
        self.workoutName = workoutName
    }
}
