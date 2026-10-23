import Foundation

enum RainIntensity: String, CaseIterable, Sendable {
    case dry
    case light
    case moderate
    case heavy

    static func classify(precipitationMM: Double, threshold: Double) -> RainIntensity {
        guard precipitationMM + 1e-9 >= threshold else { return .dry }
        if precipitationMM < 2.5 { return .light }
        if precipitationMM < 7.6 { return .moderate }
        return .heavy
    }

    var label: String {
        switch self {
        case .dry: return "Dry"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }
}
