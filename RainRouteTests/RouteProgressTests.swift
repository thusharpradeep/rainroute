import XCTest
@testable import RainRoute

final class RouteProgressTests: XCTestCase {
    func testProjectsStartMiddleAndEnd() {
        let route = TestSupport.simpleRoute(totalMeters: 30_000)

        XCTAssertEqual(
            RouteProgressTracker.project(route.coordinates[0], onto: route).distanceMeters,
            0,
            accuracy: 1
        )

        let middle = GeoCoordinate(latitude: 10.0, longitude: 76.05)
        XCTAssertEqual(
            RouteProgressTracker.project(middle, onto: route).distanceMeters,
            15_000,
            accuracy: 50
        )

        XCTAssertEqual(
            RouteProgressTracker.project(route.coordinates[1], onto: route).distanceMeters,
            30_000,
            accuracy: 1
        )
    }

    func testReportsPerpendicularOffRouteDistance() {
        let route = TestSupport.simpleRoute(totalMeters: 30_000)
        let off = GeoCoordinate(latitude: 10.01, longitude: 76.05)
        let progress = RouteProgressTracker.project(off, onto: route)

        XCTAssertEqual(progress.offRouteMeters, 1_111, accuracy: 40)
        XCTAssertEqual(progress.distanceMeters, 15_000, accuracy: 60)
        XCTAssertEqual(progress.fraction, 0.5, accuracy: 0.01)
    }

    func testClampsBeforeStartAndAfterEnd() {
        let route = TestSupport.simpleRoute(totalMeters: 30_000)

        let before = GeoCoordinate(latitude: 10.0, longitude: 75.8)
        let after = GeoCoordinate(latitude: 10.0, longitude: 76.3)

        XCTAssertEqual(
            RouteProgressTracker.project(before, onto: route).distanceMeters,
            0,
            accuracy: 1
        )
        XCTAssertEqual(
            RouteProgressTracker.project(after, onto: route).distanceMeters,
            30_000,
            accuracy: 1
        )
    }

    func testChoosesTheNearestEdge() {
        let route = Route(
            coordinates: [
                GeoCoordinate(latitude: 10.0, longitude: 76.0),
                GeoCoordinate(latitude: 10.0, longitude: 76.1),
                GeoCoordinate(latitude: 10.1, longitude: 76.1)
            ],
            cumulativeDistances: [0, 10_000, 20_000],
            cumulativeDurations: [0, 600, 1_200]
        )
        let point = GeoCoordinate(latitude: 10.05, longitude: 76.1)
        let progress = RouteProgressTracker.project(point, onto: route)

        XCTAssertEqual(progress.distanceMeters, 15_000, accuracy: 60)
        XCTAssertEqual(progress.offRouteMeters, 0, accuracy: 20)
    }

    func testArrivalUsesTolerance() {
        let route = TestSupport.simpleRoute(totalMeters: 30_000)
        let end = RouteProgress(
            distanceMeters: 29_950,
            offRouteMeters: 10,
            fraction: 0.998
        )

        XCTAssertTrue(RouteProgressTracker.hasArrived(end, route: route))
        XCTAssertFalse(
            RouteProgressTracker.hasArrived(
                RouteProgress(
                    distanceMeters: 20_000,
                    offRouteMeters: 10,
                    fraction: 0.66
                ),
                route: route
            )
        )
    }

    func testShortRouteReturnsZeroProgress() {
        let route = Route(
            coordinates: [GeoCoordinate(latitude: 10, longitude: 76)],
            cumulativeDistances: [0],
            cumulativeDurations: [0]
        )
        let progress = RouteProgressTracker.project(
            GeoCoordinate(latitude: 10, longitude: 76),
            onto: route
        )

        XCTAssertEqual(progress.distanceMeters, 0)
        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.offRouteMeters, 0)
    }
}
