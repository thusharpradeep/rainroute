import Combine
import Foundation

final class AppSettings: ObservableObject {
    static let paceKey = "rainroute.paceFactor"
    static let thresholdKey = "rainroute.wetThreshold"

    static let paceRange = 0.8...1.5
    static let thresholdRange = 0.1...2.0
    static let defaultPace = 1.0
    static let defaultThreshold = 0.2

    @Published private(set) var paceFactor: Double
    @Published private(set) var wetThreshold: Double

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedPace = defaults.object(forKey: Self.paceKey) as? Double
            ?? Self.defaultPace
        let storedThreshold = defaults.object(forKey: Self.thresholdKey) as? Double
            ?? Self.defaultThreshold

        paceFactor = min(max(storedPace, Self.paceRange.lowerBound), Self.paceRange.upperBound)
        wetThreshold = min(
            max(storedThreshold, Self.thresholdRange.lowerBound),
            Self.thresholdRange.upperBound
        )
    }

    func setPaceFactor(_ value: Double) {
        let clamped = min(max(value, Self.paceRange.lowerBound), Self.paceRange.upperBound)
        guard abs(clamped - paceFactor) > 0.0001 else { return }
        paceFactor = clamped
        defaults.set(clamped, forKey: Self.paceKey)
    }

    func setWetThreshold(_ value: Double) {
        let clamped = min(
            max(value, Self.thresholdRange.lowerBound),
            Self.thresholdRange.upperBound
        )
        guard abs(clamped - wetThreshold) > 0.0001 else { return }
        wetThreshold = clamped
        defaults.set(clamped, forKey: Self.thresholdKey)
    }
}
