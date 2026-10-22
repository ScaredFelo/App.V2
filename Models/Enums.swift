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

public enum RestCondition: Codable, Sendable, Hashable {
    case timer(seconds: Int)
    case bpmDrop(targetBpm: Int)
}
