import Foundation
import SwiftData

@Model
public final class Exercise {
    public var id: UUID
    public var name: String
    public var muscleGroupRaw: String
    public var equipmentTypeRaw: String
    public var weightTypeRaw: String?
    public var requiresStraps: Bool
    public var defaultRestConditionData: Data

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.exercise)
    public var logs: [WorkoutSetLog] = []

    @Transient
    public var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .pecho }
        set { muscleGroupRaw = newValue.rawValue }
    }

    @Transient
    public var equipmentType: EquipmentType {
        get { EquipmentType(rawValue: equipmentTypeRaw) ?? .mancuernas }
        set { equipmentTypeRaw = newValue.rawValue }
    }

    @Transient
    public var weightType: WeightType {
        get {
            guard let weightTypeRaw = weightTypeRaw,
                  let type = WeightType(rawValue: weightTypeRaw) else {
                return WeightType.defaultFor(equipmentType)
            }
            return type
        }
        set { weightTypeRaw = newValue.rawValue }
    }

    @Transient
    public var defaultRestCondition: RestCondition {
        get {
            (try? JSONDecoder().decode(RestCondition.self, from: defaultRestConditionData)) ?? .timer(seconds: 90)
        }
        set {
            defaultRestConditionData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        equipmentType: EquipmentType,
        weightType: WeightType? = nil,
        requiresStraps: Bool = false,
        defaultRestCondition: RestCondition = .timer(seconds: 90)
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.equipmentTypeRaw = equipmentType.rawValue
        self.weightTypeRaw = (weightType ?? WeightType.defaultFor(equipmentType)).rawValue
        self.requiresStraps = requiresStraps
        self.defaultRestConditionData = (try? JSONEncoder().encode(defaultRestCondition)) ?? Data()
    }
}
