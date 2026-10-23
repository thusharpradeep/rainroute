import Foundation

enum RouteError: LocalizedError, Equatable {
    case invalidRoute
    case invalidPaceFactor

    var errorDescription: String? {
        switch self {
        case .invalidRoute:
            return "The route geometry was incomplete. Try another route."
        case .invalidPaceFactor:
            return "The pace factor must be a number between 0.8 and 1.5."
        }
    }
}

/// One equal-distance slice of the route. The forecast sample is taken at
/// `midpoint`; the map draws `polyline` from the start to the end boundary.
struct RouteSegment: Identifiable, Equatable, Sendable {
    let index: Int
    let startDistanceMeters: Double
    let endDistanceMeters: Double
    let midpointDistanceMeters: Double
    let startCoordinate: GeoCoordinate
    let midpoint: GeoCoordinate
    let endCoordinate: GeoCoordinate
    let polyline: [GeoCoordinate]
    let eta: Date
    let travelTimeToMidpoint: TimeInterval

    var id: Int { index }

    var lengthMeters: Double {
        endDistanceMeters - startDistanceMeters
    }
}

enum RouteSlicer {
    static let defaultSegmentCount = 12
    static let minimumSegments = 3
    static let maximumSegments = 60

    static func clampedSegmentCount(_ requested: Int) -> Int {
        min(max(requested, minimumSegments), maximumSegments)
    }

    static func segments(
        route: Route,
        departure: Date,
        paceFactor: Double,
        segmentCount: Int = defaultSegmentCount
    ) throws -> [RouteSegment] {
        try validate(route)
        guard paceFactor.isFinite else {
            throw RouteError.invalidPaceFactor
        }
        let pace = min(max(paceFactor, 0.8), 1.5)
        let count = clampedSegmentCount(segmentCount)
        let totalDistance = route.totalDistanceMeters

        return (0..<count).map { index in
            let startDistance = totalDistance * Double(index) / Double(count)
            let endDistance = totalDistance * Double(index + 1) / Double(count)
            let midpointDistance = (startDistance + endDistance) / 2
            let midpointDuration = duration(
                at: midpointDistance,
                route: route
            )

            return RouteSegment(
                index: index,
                startDistanceMeters: startDistance,
                endDistanceMeters: endDistance,
                midpointDistanceMeters: midpointDistance,
                startCoordinate: coordinate(at: startDistance, route: route),
                midpoint: coordinate(at: midpointDistance, route: route),
                endCoordinate: coordinate(at: endDistance, route: route),
                polyline: polyline(from: startDistance, to: endDistance, route: route),
                eta: departure.addingTimeInterval(pace * midpointDuration),
                travelTimeToMidpoint: pace * midpointDuration
            )
        }
    }

    /// Unique snapped cells for every segment midpoint, in first-seen route order.
    static func gridCells(
        route: Route,
        segmentCount: Int = defaultSegmentCount
    ) throws -> [GridCell] {
        try validate(route)
        let count = clampedSegmentCount(segmentCount)
        let totalDistance = route.totalDistanceMeters
        var seen = Set<GridCell>()
        var cells: [GridCell] = []

        for index in 0..<count {
            let midpoint = totalDistance * (Double(index) + 0.5) / Double(count)
            let cell = GridCell(coordinate: coordinate(at: midpoint, route: route))
            if seen.insert(cell).inserted {
                cells.append(cell)
            }
        }
        return cells
    }

    static func coordinate(at distance: Double, route: Route) -> GeoCoordinate {
        guard let first = route.coordinates.first else {
            return GeoCoordinate(latitude: 0, longitude: 0)
        }
        guard route.coordinates.count > 1 else { return first }

        let clamped = min(max(distance, 0), route.totalDistanceMeters)
        let index = upperBound(of: clamped, in: route.cumulativeDistances)
        guard index > 0 else { return route.coordinates[0] }
        guard index < route.coordinates.count else {
            return route.coordinates[route.coordinates.count - 1]
        }

        let previousIndex = index - 1
        let distanceSpan = route.cumulativeDistances[index]
            - route.cumulativeDistances[previousIndex]
        let fraction: Double
        if distanceSpan > 0 {
            fraction = (clamped - route.cumulativeDistances[previousIndex]) / distanceSpan
        } else {
            fraction = 0
        }

        let start = route.coordinates[previousIndex]
        let end = route.coordinates[index]
        return GeoCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }

    static func duration(at distance: Double, route: Route) -> TimeInterval {
        guard route.cumulativeDurations.count > 1 else {
            return route.cumulativeDurations.first ?? 0
        }

        let clamped = min(max(distance, 0), route.totalDistanceMeters)
        let index = upperBound(of: clamped, in: route.cumulativeDistances)
        guard index > 0 else { return route.cumulativeDurations[0] }
        guard index < route.cumulativeDurations.count else {
            return route.cumulativeDurations[route.cumulativeDurations.count - 1]
        }

        let previousIndex = index - 1
        let distanceSpan = route.cumulativeDistances[index]
            - route.cumulativeDistances[previousIndex]
        let fraction = distanceSpan > 0
            ? (clamped - route.cumulativeDistances[previousIndex]) / distanceSpan
            : 0
        let start = route.cumulativeDurations[previousIndex]
        let end = route.cumulativeDurations[index]
        return start + (end - start) * fraction
    }

    private static func polyline(
        from startDistance: Double,
        to endDistance: Double,
        route: Route
    ) -> [GeoCoordinate] {
        var points: [GeoCoordinate] = [coordinate(at: startDistance, route: route)]
        let epsilon = 0.001

        for index in route.coordinates.indices {
            let distance = route.cumulativeDistances[index]
            guard distance > startDistance + epsilon,
                  distance < endDistance - epsilon else {
                continue
            }
            let point = route.coordinates[index]
            if points.last != point {
                points.append(point)
            }
        }

        let endPoint = coordinate(at: endDistance, route: route)
        if points.last != endPoint {
            points.append(endPoint)
        }
        if points.count == 1 {
            points.append(endPoint)
        }
        return points
    }

    /// Index of the first value greater than or equal to `value`. Returns
    /// `values.count` when every value is smaller.
    private static func upperBound(of value: Double, in values: [Double]) -> Int {
        guard !values.isEmpty else { return 0 }
        var low = 0
        var high = values.count
        while low < high {
            let middle = (low + high) / 2
            if values[middle] < value {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private static func validate(_ route: Route) throws {
        guard route.coordinates.count >= 2,
              route.cumulativeDistances.count == route.coordinates.count,
              route.cumulativeDurations.count == route.coordinates.count,
              route.cumulativeDistances.first == 0,
              route.cumulativeDurations.first == 0,
              route.totalDistanceMeters.isFinite,
              route.totalDurationSeconds.isFinite,
              route.totalDistanceMeters > 0,
              route.totalDurationSeconds > 0 else {
            throw RouteError.invalidRoute
        }

        for index in 1..<route.coordinates.count {
            guard route.cumulativeDistances[index] >= route.cumulativeDistances[index - 1],
                  route.cumulativeDurations[index] >= route.cumulativeDurations[index - 1] else {
                throw RouteError.invalidRoute
            }
        }
    }
}
