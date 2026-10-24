import ActivityKit
import Foundation

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentBPM: Int
        public var elapsedTime: TimeInterval
        public var isPaused: Bool

        public init(currentBPM: Int, elapsedTime: TimeInterval, isPaused: Bool) {
            self.currentBPM = currentBPM
            self.elapsedTime = elapsedTime
            self.isPaused = isPaused
        }
    }

    public var workoutName: String

    public init(workoutName: String) {
        self.workoutName = workoutName
    }
}
