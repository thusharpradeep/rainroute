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
        totalDistanceMeters * wetDistanceShare
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
        forecasts: [GridCell: HourlyForecast],
        segmentCount: Int = RouteSlicer.defaultSegmentCount
    ) throws -> WetnessResult {
        guard threshold.isFinite, threshold > 0 else {
            throw WetnessError.invalidThreshold
        }

        let segments = try RouteSlicer.segments(
            route: route,
            departure: departure,
            paceFactor: paceFactor,
            segmentCount: segmentCount
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

    /// Evaluates only the part of the route still ahead during a live ride.
    ///
    /// Segment ETAs keep the planned pace but are anchored to `now`, so no
    /// forecast is requested for hours already ridden through. A partially
    /// passed segment is weighted by its remaining length, and segment numbers
    /// keep their original 1-based positions.
    static func evaluateRemaining(
        route: Route,
        now: Date,
        paceFactor: Double,
        threshold: Double,
        forecasts: [GridCell: HourlyForecast],
        segmentCount: Int = RouteSlicer.defaultSegmentCount,
        progressDistanceMeters: Double,
        remainingDuration: TimeInterval
    ) throws -> WetnessResult? {
        guard threshold.isFinite, threshold > 0 else {
            throw WetnessError.invalidThreshold
        }
        guard remainingDuration.isFinite, remainingDuration > 0 else {
            return nil
        }

        let pace = min(max(paceFactor, 0.8), 1.5)
        let progress = min(max(progressDistanceMeters, 0), route.totalDistanceMeters)
        guard progress < route.totalDistanceMeters else { return nil }

        let elapsed = pace * RouteSlicer.duration(at: progress, route: route)
        let segments = try RouteSlicer.segments(
            route: route,
            departure: now.addingTimeInterval(-elapsed),
            paceFactor: pace,
            segmentCount: segmentCount
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
            let remainingLength = min(segment.endDistanceMeters, route.totalDistanceMeters)
                - max(segment.startDistanceMeters, progress)
            guard remainingLength > 0.001 else { continue }

            let cell = GridCell(coordinate: segment.midpoint)
            guard let forecast = forecasts[cell] else {
                throw WetnessError.missingForecast(cell)
            }
            // The midpoint of a partially passed segment can be behind the
            // rider. Sample "now" instead of asking for a past forecast hour.
            let sampleTime = max(segment.eta, now)
            guard let hour = forecast.hour(containing: sampleTime) else {
                throw WetnessError.missingForecastHour(cell, sampleTime)
            }

            let precipitation = max(0, hour.precipitationMM)
            let isWet = precipitation + 1e-9 >= threshold
            let intensity = RainIntensity.classify(
                precipitationMM: precipitation,
                threshold: threshold
            )

            if isWet {
                wetCount += 1
                wetDistance += remainingLength
            }
            if let probability = hour.probability {
                probabilitySum += remainingLength * probability
                probabilityDistance += remainingLength
            } else {
                hasEveryProbability = false
            }
            totalDistance += remainingLength

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

        guard totalDistance > 0.001, !assessments.isEmpty else { return nil }

        let wetShare = wetDistance / totalDistance
        let probabilityShare = hasEveryProbability && probabilityDistance > 0
            ? min(max(probabilitySum / probabilityDistance, 0), 1)
            : nil

        return WetnessResult(
            departure: now,
            paceFactor: pace,
            threshold: threshold,
            segments: assessments,
            totalDistanceMeters: totalDistance,
            totalDurationSeconds: remainingDuration,
            wetSegmentCount: wetCount,
            wetDistanceShare: wetShare,
            probabilityWeightedShare: probabilityShare
        )
    }
}
