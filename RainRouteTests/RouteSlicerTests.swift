import XCTest
@testable import RainRoute

final class RouteSlicerTests: XCTestCase {
    func testSegmentCountDefaultsAndClampsToTheSupportedRange() {
        XCTAssertEqual(RouteSlicer.defaultSegmentCount, 12)
        XCTAssertEqual(RouteSlicer.clampedSegmentCount(-1), 3)
        XCTAssertEqual(RouteSlicer.clampedSegmentCount(3), 3)
        XCTAssertEqual(RouteSlicer.clampedSegmentCount(12), 12)
        XCTAssertEqual(RouteSlicer.clampedSegmentCount(60), 60)
        XCTAssertEqual(RouteSlicer.clampedSegmentCount(999), 60)
    }

    func testCustomSegmentCountProducesEqualLengthsAndEtas() throws {
        let route = TestSupport.simpleRoute(totalMeters: 60_000, durationSeconds: 3_600)
        let segments = try RouteSlicer.segments(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            segmentCount: 6
        )

        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments[0].lengthMeters, 10_000, accuracy: 0.001)
        XCTAssertEqual(segments[0].travelTimeToMidpoint, 300, accuracy: 0.001)
        XCTAssertEqual(segments[5].endDistanceMeters, 60_000, accuracy: 0.001)
    }

    func testTwelveSegmentsHaveEqualLengthsAndMidpointEtas() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let departure = TestSupport.date(hour: 10)
        let segments = try RouteSlicer.segments(
            route: route,
            departure: departure,
            paceFactor: 1.0
        )

        XCTAssertEqual(segments.count, 12)
        XCTAssertEqual(segments.first?.startDistanceMeters ?? -1, 0)
        XCTAssertEqual(segments.last?.endDistanceMeters ?? 0, 120_000, accuracy: 0.001)

        for (index, segment) in segments.enumerated() {
            XCTAssertEqual(segment.lengthMeters, 10_000, accuracy: 0.001)
            XCTAssertEqual(segment.midpointDistanceMeters, 5_000 + Double(index) * 10_000, accuracy: 0.001)
            XCTAssertEqual(
                segment.travelTimeToMidpoint,
                300 + Double(index) * 600,
                accuracy: 0.001
            )
            XCTAssertEqual(
                segment.eta.timeIntervalSince1970,
                departure.addingTimeInterval(segment.travelTimeToMidpoint).timeIntervalSince1970,
                accuracy: 0.001
            )
        }
    }

    func testPaceFactorScalesTheMidpointEta() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let departure = TestSupport.date(hour: 10)
        let normal = try RouteSlicer.segments(route: route, departure: departure, paceFactor: 1.0)
        let slow = try RouteSlicer.segments(route: route, departure: departure, paceFactor: 1.5)

        XCTAssertEqual(normal[0].travelTimeToMidpoint, 300, accuracy: 0.001)
        XCTAssertEqual(slow[0].travelTimeToMidpoint, 450, accuracy: 0.001)
        XCTAssertEqual(
            slow[0].eta.timeIntervalSince(normal[0].eta),
            150,
            accuracy: 0.001
        )
    }

    func testSegmentPolylinesMeetTheirBoundaries() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let segments = try RouteSlicer.segments(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0
        )

        for segment in segments {
            let first = try XCTUnwrap(segment.polyline.first)
            let last = try XCTUnwrap(segment.polyline.last)
            XCTAssertEqual(first, segment.startCoordinate)
            XCTAssertEqual(last, segment.endCoordinate)
            XCTAssertGreaterThanOrEqual(segment.polyline.count, 2)
        }
    }

    func testCoordinateAndDurationInterpolationAtEndpointsAndMiddle() throws {
        let route = TestSupport.simpleRoute(totalMeters: 100_000, durationSeconds: 10_000)

        XCTAssertEqual(RouteSlicer.coordinate(at: 0, route: route), try XCTUnwrap(route.coordinates.first))
        XCTAssertEqual(RouteSlicer.coordinate(at: 100_000, route: route), try XCTUnwrap(route.coordinates.last))
        XCTAssertEqual(RouteSlicer.duration(at: 0, route: route), 0, accuracy: 0.001)
        XCTAssertEqual(RouteSlicer.duration(at: 50_000, route: route), 5_000, accuracy: 0.001)

        let midpoint = RouteSlicer.coordinate(at: 50_000, route: route)
        XCTAssertEqual(midpoint.latitude, 10.0, accuracy: 0.000001)
        XCTAssertEqual(midpoint.longitude, 76.05, accuracy: 0.000001)
    }

    func testGridCellsSnapToTenthsAndDeduplicate() throws {
        XCTAssertEqual(
            GridCell(coordinate: GeoCoordinate(latitude: 10.96, longitude: 75.94)),
            GridCell(latitudeTenths: 110, longitudeTenths: 759)
        )
        XCTAssertEqual(
            GridCell(coordinate: GeoCoordinate(latitude: -10.96, longitude: -75.94)),
            GridCell(latitudeTenths: -110, longitudeTenths: -759)
        )

        let route = TestSupport.tirurKochiRoute()
        let cells = try RouteSlicer.gridCells(route: route)
        XCTAssertEqual(cells.count, Set(cells).count)
        XCTAssertFalse(cells.isEmpty)

        let three = try RouteSlicer.gridCells(route: route, segmentCount: 3)
        XCTAssertEqual(three.count, 3)
        let sixty = try RouteSlicer.gridCells(route: route, segmentCount: 60)
        XCTAssertGreaterThan(sixty.count, 3)
        XCTAssertLessThan(sixty.count, 60)
        XCTAssertEqual(sixty.count, Set(sixty).count)
    }

    func testInvalidRouteThrows() {
        let invalid = Route(
            coordinates: [GeoCoordinate(latitude: 10, longitude: 76)],
            cumulativeDistances: [0],
            cumulativeDurations: [0]
        )
        XCTAssertThrowsError(
            try RouteSlicer.segments(
                route: invalid,
                departure: TestSupport.date(hour: 10),
                paceFactor: 1.0
            )
        ) { error in
            XCTAssertEqual(error as? RouteError, RouteError.invalidRoute)
        }
    }

    func testPaceFactorIsClampedToSupportedRange() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let departure = TestSupport.date(hour: 10)
        let fast = try RouteSlicer.segments(route: route, departure: departure, paceFactor: 2.0)
        let clamped = try RouteSlicer.segments(route: route, departure: departure, paceFactor: 1.5)
        XCTAssertEqual(fast[0].eta, clamped[0].eta)
    }
}
