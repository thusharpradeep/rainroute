import XCTest
@testable import RainRoute

final class LiveWetnessTests: XCTestCase {
    func testRemainingResultDropsPassedSegmentsAndKeepsOriginalNumbers() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [(0.5, 0.8), (0.5, 0.8), (0.5, 0.8)]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let all = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            segmentCount: 12
        )

        let live = try XCTUnwrap(
            all.remaining(
                after: 55_000,
                at: TestSupport.date(hour: 10, minute: 30),
                remainingDuration: 3_900
            )
        )

        XCTAssertEqual(live.segments.first?.segment.index, 5)
        XCTAssertEqual((live.segments.first?.segment.index ?? 0) + 1, 6)
        XCTAssertEqual(live.totalSegments, 7)
        XCTAssertEqual(live.departure, TestSupport.date(hour: 10, minute: 30))
        XCTAssertEqual(live.totalDistanceMeters, 65_000, accuracy: 0.001)
        XCTAssertEqual(live.totalDurationSeconds, 3_900, accuracy: 0.001)
        XCTAssertEqual(live.arrival, TestSupport.date(hour: 11, minute: 35))
        XCTAssertEqual(live.wetDistanceShare, 1.0, accuracy: 0.0001)
        XCTAssertEqual(live.wetSegmentIndices, [6, 7, 8, 9, 10, 11, 12])
    }

    func testRemainingResultWeightsPartiallyPassedSegmentByRemainingLength() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let wet = TestSupport.hourlyForecast(
            startHour: 10,
            values: [(0.0, 0.0), (0.5, 1.0), (0.0, 0.0), (0.0, 0.0)]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: wet)
        let all = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            segmentCount: 12
        )

        let live = try XCTUnwrap(
            all.remaining(
                after: 5_000,
                at: TestSupport.date(hour: 10, minute: 10),
                remainingDuration: 6_600
            )
        )

        XCTAssertEqual(live.totalDistanceMeters, 115_000, accuracy: 0.001)
        XCTAssertEqual(live.segments.first?.segment.index, 0)
        XCTAssertEqual(live.segments.count, 12)
        XCTAssertEqual(live.wetSegmentCount, 6)
        XCTAssertEqual(live.wetSegmentIndices, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(live.wetDistanceShare, 55_000 / 115_000, accuracy: 0.0001)
    }

    func testRemainingResultIsNilAtTheDestination() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let forecasts = try TestSupport.uniformForecasts(
            route: route,
            forecast: TestSupport.hourlyForecast(startHour: 10, values: [(0.0, 0.0)])
        )
        let all = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            segmentCount: 12
        )

        XCTAssertNil(
            all.remaining(
                after: 30_000,
                at: TestSupport.date(hour: 11),
                remainingDuration: 0
            )
        )
    }

    func testWetSegmentSummaryNamesSegmentsOrStatesNoneOrAll() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let dry = TestSupport.hourlyForecast(startHour: 11, values: [(0.0, 0.0)])
        let wet = TestSupport.hourlyForecast(startHour: 11, values: [(1.0, 1.0)])

        let dryResult = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: try TestSupport.uniformForecasts(route: route, forecast: dry)
        )
        XCTAssertEqual(dryResult.wetSegmentSummary, "No segments are forecast wet.")

        let wetResult = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: try TestSupport.uniformForecasts(route: route, forecast: wet)
        )
        XCTAssertEqual(wetResult.wetSegmentSummary, "All 12 segments are forecast wet.")
        XCTAssertEqual(wetResult.wetSegmentIndices, Array(1...12))
    }
}
