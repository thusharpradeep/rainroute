import Foundation

/// Route geometry with a cumulative distance/time profile.
///
/// `coordinates`, `cumulativeDistances`, and `cumulativeDurations` always have the
/// same count. The first element of each cumulative array is zero. Distances are in
/// metres and durations in seconds.
struct Route: Equatable, Sendable {
    let coordinates: [GeoCoordinate]
    let cumulativeDistances: [Double]
    let cumulativeDurations: [Double]

    var totalDistanceMeters: Double {
        cumulativeDistances.last ?? 0
    }

    var totalDurationSeconds: TimeInterval {
        cumulativeDurations.last ?? 0
    }

    /// Builds a route from coordinates with a constant-speed timing profile scaled
    /// to the supplied totals. Used by tests and as a last-resort fallback when OSRM
    /// omits usable annotations.
    static func synthetic(
        coordinates: [GeoCoordinate],
        totalDistanceMeters: Double,
        totalDurationSeconds: TimeInterval
    ) -> Route {
        guard coordinates.count >= 2 else {
            return Route(
                coordinates: coordinates,
                cumulativeDistances: [0],
                cumulativeDurations: [0]
            )
        }

        var rawDistances = [0.0]
        for index in 1..<coordinates.count {
            rawDistances.append(
                rawDistances[index - 1]
                    + coordinates[index - 1].distance(to: coordinates[index])
            )
        }

        let rawTotal = rawDistances.last ?? 0
        let distanceScale = rawTotal > 0 ? totalDistanceMeters / rawTotal : 0
        let distances = rawDistances.map { $0 * distanceScale }
        let durations = rawTotal > 0
            ? rawDistances.map { ($0 / rawTotal) * totalDurationSeconds }
            : rawDistances.map { _ in 0 }

        return Route(
            coordinates: coordinates,
            cumulativeDistances: distances,
            cumulativeDurations: durations
        )
    }
}
