import Foundation

public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Identifiable {
    case pecho = "Pecho"
    case espalda = "Espalda"
    case hombros = "Hombros"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case cuadriceps = "Cuadriceps"
    case isquios = "Isquios"
    case gemelos = "Gemelos"
    case abdominales = "Abdominales"
    case gluteos = "Gluteos"

    public var id: String { rawValue }
}

public enum EquipmentType: String, Codable, CaseIterable, Sendable, Identifiable {
    case mancuernas = "Mancuernas"
    case poleas = "Poleas"
    case barraFija = "Barra Fija"
    case discosMaquina = "Discos para Máquina"
    case multipower = "Multipower"
    case barraOlimpica = "Barra Olímpica"
    case barraEZ = "Barra EZ"

    public var id: String { rawValue }
}

public enum WeightType: String, Codable, CaseIterable, Sendable, Identifiable {
    case mancuernas = "Mancuernas"
    case discos = "Discos"
    case polea = "Polea"
    case barra = "Barra"
    case maquina = "Máquina"
    case pesoCorporal = "Peso Corporal"
    case bandaElastica = "Banda Elástica"
    case kettlebell = "Kettlebell"
    case otro = "Otro"

    public var id: String { rawValue }

    public static func defaultFor(_ equipment: EquipmentType) -> WeightType {
        switch equipment {
        case .mancuernas:
            return .mancuernas
        case .poleas:
            return .polea
        case .barraFija:
            return .pesoCorporal
        case .discosMaquina:
            return .discos
        case .multipower, .barraOlimpica, .barraEZ:
            return .barra
        }
    }
}

public enum RestCondition: Codable, Sendable, Hashable {
    case timer(seconds: Int)
    case bpmDrop(targetBpm: Int)
}
