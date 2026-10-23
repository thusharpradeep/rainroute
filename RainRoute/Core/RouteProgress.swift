import Foundation

/// Where the rider is along the planned route.
struct RouteProgress: Equatable, Sendable {
    /// Along-route distance of the nearest point on the polyline.
    let distanceMeters: Double
    /// Distance from the GPS fix to that nearest point.
    let offRouteMeters: Double
    /// `distanceMeters` divided by the route's total distance, clamped to 0...1.
    let fraction: Double
}

enum RouteProgressTracker {
    /// Projects a coordinate onto the nearest route edge using a local
    /// equirectangular approximation. Good enough at ride scale and testable
    /// without CoreLocation.
    static func project(_ point: GeoCoordinate, onto route: Route) -> RouteProgress {
        guard route.coordinates.count >= 2,
              route.cumulativeDistances.count == route.coordinates.count,
              route.cumulativeDurations.count == route.coordinates.count else {
            return RouteProgress(distanceMeters: 0, offRouteMeters: 0, fraction: 0)
        }

        var best: (along: Double, offRoute: Double)?
        for index in 0..<(route.coordinates.count - 1) {
            let start = route.coordinates[index]
            let end = route.coordinates[index + 1]
            let midpointLatitude = (start.latitude + end.latitude) / 2 * .pi / 180
            let metersPerDegreeLongitude: Double = 111_320 * cos(midpointLatitude)
            let metersPerDegreeLatitude: Double = 110_540

            let edgeX = (end.longitude - start.longitude) * metersPerDegreeLongitude
            let edgeY = (end.latitude - start.latitude) * metersPerDegreeLatitude
            let pointX = (point.longitude - start.longitude) * metersPerDegreeLongitude
            let pointY = (point.latitude - start.latitude) * metersPerDegreeLatitude

            let lengthSquared = edgeX * edgeX + edgeY * edgeY
            let projection = lengthSquared > 0
                ? (pointX * edgeX + pointY * edgeY) / lengthSquared
                : 0
            let clamped = min(max(projection, 0), 1)
            let deltaX = pointX - edgeX * clamped
            let deltaY = pointY - edgeY * clamped
            let offRoute = sqrt(deltaX * deltaX + deltaY * deltaY)

            let edgeSpan = route.cumulativeDistances[index + 1]
                - route.cumulativeDistances[index]
            let along = route.cumulativeDistances[index] + edgeSpan * clamped

            if let current = best {
                if offRoute < current.offRoute - 0.001
                    || (abs(offRoute - current.offRoute) <= 0.001 && along < current.along) {
                    best = (along, offRoute)
                }
            } else {
                best = (along, offRoute)
            }
        }

        guard let best else {
            return RouteProgress(distanceMeters: 0, offRouteMeters: 0, fraction: 0)
        }

        let clampedDistance = min(
            max(best.along, 0),
            max(route.totalDistanceMeters, 0)
        )
        let fraction = route.totalDistanceMeters > 0
            ? min(max(clampedDistance / route.totalDistanceMeters, 0), 1)
            : 0

        return RouteProgress(
            distanceMeters: clampedDistance,
            offRouteMeters: best.offRoute,
            fraction: fraction
        )
    }

    static func hasArrived(
        _ progress: RouteProgress,
        route: Route,
        tolerance: Double = 120
    ) -> Bool {
        progress.distanceMeters >= route.totalDistanceMeters - max(0, tolerance)
    }
}
