import Foundation

enum WetnessError: LocalizedError, Equatable {
    case invalidThreshold
    case missingForecast(GridCell)
    case missingForecastHour(GridCell, Date)

    var errorDescription: String? {
        switch self {
        case .invalidThreshold:
            return "The rain threshold must be greater than zero."
        case .missingForecast(let cell):
            return "No forecast was available for the route cell \(cell.id). Try again in a moment."
        case .missingForecastHour(let cell, let date):
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            return "The forecast for cell \(cell.id) does not cover \(formatted). Try a shorter ride or refresh the forecast."
        }
    }
}

struct SegmentAssessment: Identifiable, Equatable, Sendable {
    let segment: RouteSegment
    let forecastHour: Date
    let precipitationMM: Double
    let probability: Double?
    let isWet: Bool
    let intensity: RainIntensity

    var id: Int { segment.id }
}

struct WetnessResult: Equatable, Sendable {
    let departure: Date
    let paceFactor: Double
    let threshold: Double
    let segments: [SegmentAssessment]
    let totalDistanceMeters: Double
    /// Pace-adjusted travel time for the whole route.
    let totalDurationSeconds: TimeInterval
    let wetSegmentCount: Int
    let wetDistanceShare: Double
    let probabilityWeightedShare: Double?

    var totalSegments: Int { segments.count }

    var arrival: Date {
        departure.addingTimeInterval(totalDurationSeconds)
    }

    var roundedWetPercent: Int {
        guard wetDistanceShare > 0 else { return 0 }
        let raw = wetDistanceShare * 100
        return min(100, max(0, Int((raw / 5).rounded()) * 5))
    }

    var wetDistanceMeters: Double {
        segments
            .filter(\.isWet)
            .reduce(0) { $0 + $1.segment.lengthMeters }
    }

    var usesProbability: Bool {
        probabilityWeightedShare != nil
    }
}

enum WetnessEngine {
    static func evaluate(
        route: Route,
        departure: Date,
        paceFactor: Double,
        threshold: Double,
        forecasts: [GridCell: HourlyForecast]
    ) throws -> WetnessResult {
        guard threshold.isFinite, threshold > 0 else {
            throw WetnessError.invalidThreshold
        }

        let segments = try RouteSlicer.segments(
            route: route,
            departure: departure,
            paceFactor: paceFactor
        )

        var assessments: [SegmentAssessment] = []
        assessments.reserveCapacity(segments.count)

        var wetCount = 0
        var wetDistance = 0.0
        var probabilitySum = 0.0
        var probabilityDistance = 0.0
        var totalDistance = 0.0
        var hasEveryProbability = true

        for segment in segments {
            let cell = GridCell(coordinate: segment.midpoint)
            guard let forecast = forecasts[cell] else {
                throw WetnessError.missingForecast(cell)
            }
            guard let hour = forecast.hour(containing: segment.eta) else {
                throw WetnessError.missingForecastHour(cell, segment.eta)
            }

            let precipitation = max(0, hour.precipitationMM)
            let isWet = precipitation + 1e-9 >= threshold
            let intensity = RainIntensity.classify(
                precipitationMM: precipitation,
                threshold: threshold
            )

            if isWet {
                wetCount += 1
                wetDistance += segment.lengthMeters
            }
            if let probability = hour.probability {
                probabilitySum += segment.lengthMeters * probability
                probabilityDistance += segment.lengthMeters
            } else {
                hasEveryProbability = false
            }
            totalDistance += segment.lengthMeters

            assessments.append(
                SegmentAssessment(
                    segment: segment,
                    forecastHour: hour.time,
                    precipitationMM: precipitation,
                    probability: hour.probability,
                    isWet: isWet,
                    intensity: intensity
                )
            )
        }

        let pace = min(max(paceFactor, 0.8), 1.5)
        let wetShare = totalDistance > 0 ? wetDistance / totalDistance : 0
        let probabilityShare = hasEveryProbability && probabilityDistance > 0
            ? min(max(probabilitySum / probabilityDistance, 0), 1)
            : nil

        return WetnessResult(
            departure: departure,
            paceFactor: pace,
            threshold: threshold,
            segments: assessments,
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: pace * route.totalDurationSeconds,
            wetSegmentCount: wetCount,
            wetDistanceShare: wetShare,
            probabilityWeightedShare: probabilityShare
        )
    }
}
