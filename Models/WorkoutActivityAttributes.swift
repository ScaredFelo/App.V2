import Foundation
import ActivityKit

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var timerEndDate: Date
        public var currentBPM: Int
        public var targetBPM: Int
        public var exerciseName: String
        public var isBpmMode: Bool

        public init(
            timerEndDate: Date,
            currentBPM: Int,
            targetBPM: Int,
            exerciseName: String,
            isBpmMode: Bool
        ) {
            self.timerEndDate = timerEndDate
            self.currentBPM = currentBPM
            self.targetBPM = targetBPM
            self.exerciseName = exerciseName
            self.isBpmMode = isBpmMode
        }
    }

    public var routineName: String

    public init(routineName: String) {
        self.routineName = routineName
    }
}
