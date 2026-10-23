import SwiftUI
import UIKit

enum Theme {
    static let accent = Color.accentColor
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .systemBackground)
    static let hairline = Color(uiColor: .separator)
    static let launchBackground = Color(red: 0.03, green: 0.09, blue: 0.16)

    static let dry = Color(red: 0.44, green: 0.50, blue: 0.58)
    static let lightRain = Color(red: 0.20, green: 0.70, blue: 0.92)
    static let moderateRain = Color(red: 0.10, green: 0.42, blue: 0.88)
    static let heavyRain = Color(red: 0.45, green: 0.22, blue: 0.78)

    static let safe = Color(red: 0.12, green: 0.60, blue: 0.40)
    static let caution = Color(red: 0.91, green: 0.57, blue: 0.10)
    static let danger = Color(red: 0.84, green: 0.24, blue: 0.23)

    static func riskColor(for percent: Int) -> Color {
        switch percent {
        case 0...5: return safe
        case 6...35: return caution
        default: return danger
        }
    }

    static func riskLabel(for percent: Int) -> String {
        switch percent {
        case 0...5: return "Mostly dry"
        case 6...35: return "Some rain"
        default: return "Very wet"
        }
    }
}

extension RainIntensity {
    var color: Color {
        switch self {
        case .dry: return Theme.dry
        case .light: return Theme.lightRain
        case .moderate: return Theme.moderateRain
        case .heavy: return Theme.heavyRain
        }
    }
}
