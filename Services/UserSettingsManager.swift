import Foundation

enum UserSettingsManager {
    static let multipowerBarWeightKey = "multipowerBarWeight"
    static let availablePlatesKey = "availablePlates"
    static let isBigPictureModeEnabledKey = "isBigPictureModeEnabled"

    static let defaultBarWeight: Double = 20
    static let plateOptions: [Double] = [0.5, 1.25, 2.5, 5, 10, 15, 20, 25]

    static var defaultAvailablePlates: String {
        serializePlates(Set(plateOptions))
    }

    static func parsePlates(_ raw: String) -> [Double] {
        raw.split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .sorted()
    }

    static func serializePlates(_ plates: Set<Double>) -> String {
        plates.sorted().map(formatted).joined(separator: ",")
    }

    static func formatted(_ weight: Double) -> String {
        weight == weight.rounded() ? String(Int(weight)) : String(weight)
    }
}
