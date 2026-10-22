import Foundation
import ActivityKit

public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var remainingSeconds: Int
        public var currentBPM: Int
        public var targetBPM: Int
        public var exerciseName: String
        public var isBpmMode: Bool

        public init(
            remainingSeconds: Int,
            currentBPM: Int,
            targetBPM: Int,
            exerciseName: String,
            isBpmMode: Bool
        ) {
            self.remainingSeconds = remainingSeconds
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
