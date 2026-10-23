import XCTest
@testable import RainRoute

final class WetnessEngineTests: XCTestCase {
    func testTirurKochiFixtureCountsWetSegmentsAtEta() throws {
        let route = TestSupport.tirurKochiRoute()
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [
                (0.0, 0.1),
                (0.6, 0.8),
                (0.6, 0.8),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1)
            ]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let result = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertEqual(result.totalSegments, 13)
        XCTAssertEqual(result.wetSegmentCount, 11)
        XCTAssertEqual(result.roundedWetPercent, 85)
        XCTAssertEqual(result.totalDistanceMeters, 128_870, accuracy: 0.01)
        XCTAssertEqual(result.totalDurationSeconds, 8_678, accuracy: 0.01)
        XCTAssertEqual(
            result.probabilityWeightedShare ?? -1,
            (11 * 0.8 + 2 * 0.1) / 13,
            accuracy: 0.0001
        )
    }

    func testThresholdEqualityAndIntensityClassification() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let cells = try RouteSlicer.gridCells(route: route)
        XCTAssertEqual(cells.count, 3)

        let forecasts: [GridCell: HourlyForecast] = [
            cells[0]: TestSupport.hourlyForecast(startHour: 11, values: [(0.2, 0.5), (0.0, 0.1)]),
            cells[1]: TestSupport.hourlyForecast(startHour: 11, values: [(0.199, 0.5), (0.0, 0.1)]),
            cells[2]: TestSupport.hourlyForecast(startHour: 11, values: [(2.5, 1.0), (0.0, 0.1)])
        ]

        let result = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertEqual(result.wetSegmentCount, 2)
        XCTAssertEqual(result.wetDistanceShare, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(result.roundedWetPercent, 65)
        XCTAssertEqual(result.segments[0].intensity, .light)
        XCTAssertEqual(result.segments[1].intensity, .dry)
        XCTAssertEqual(result.segments[2].intensity, .moderate)
        XCTAssertEqual(result.probabilityWeightedShare ?? -1, 2.0 / 3.0, accuracy: 0.0001)
    }

    func testProbabilityIsSeparateFromTheHeadline() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let forecast = TestSupport.hourlyForecast(
            startHour: 11,
            values: [(0.0, 0.9), (0.0, 0.1)]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let result = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertEqual(result.wetSegmentCount, 0)
        XCTAssertEqual(result.roundedWetPercent, 0)
        XCTAssertEqual(result.probabilityWeightedShare ?? -1, 0.9, accuracy: 0.0001)
    }

    func testMissingProbabilityLeavesConfidenceUnavailable() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let forecast = TestSupport.hourlyForecast(
            startHour: 11,
            values: [(0.5, nil), (0.0, nil)]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let result = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertNil(result.probabilityWeightedShare)
        XCTAssertFalse(result.usesProbability)
    }

    func testPaceFactorCanMoveSegmentsIntoAnotherHourlyBucket() throws {
        let route = TestSupport.simpleRoute(totalMeters: 120_000, durationSeconds: 7_200)
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [
                (0.0, 0.1),
                (0.6, 0.8),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1)
            ]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)

        let normal = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )
        let slow = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.5,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertEqual(normal.totalSegments, 12)
        XCTAssertEqual(normal.wetSegmentCount, 6)
        XCTAssertEqual(slow.wetSegmentCount, 4)
        XCTAssertNotEqual(normal.wetSegmentCount, slow.wetSegmentCount)
    }

    func testMissingForecastThrows() throws {
        let route = TestSupport.simpleRoute()
        XCTAssertThrowsError(
            try WetnessEngine.evaluate(
                route: route,
                departure: TestSupport.date(hour: 10),
                paceFactor: 1.0,
                threshold: 0.2,
                forecasts: [:]
            )
        ) { error in
            guard let wetnessError = error as? WetnessError,
                  case .missingForecast = wetnessError else {
                return XCTFail("Expected missingForecast, got \(error)")
            }
        }
    }

    func testMissingForecastHourThrows() throws {
        let route = TestSupport.simpleRoute()
        let forecast = TestSupport.hourlyForecast(startHour: 11, values: [(0.1, 0.5)])
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)

        XCTAssertThrowsError(
            try WetnessEngine.evaluate(
                route: route,
                departure: TestSupport.date(hour: 12),
                paceFactor: 1.0,
                threshold: 0.2,
                forecasts: forecasts
            )
        ) { error in
            guard let wetnessError = error as? WetnessError,
                  case .missingForecastHour = wetnessError else {
                return XCTFail("Expected missingForecastHour, got \(error)")
            }
        }
    }

    func testInvalidThresholdThrows() throws {
        let route = TestSupport.simpleRoute()
        let forecasts = try TestSupport.uniformForecasts(
            route: route,
            forecast: TestSupport.hourlyForecast(startHour: 11, values: [(0.1, 0.5)])
        )
        XCTAssertThrowsError(
            try WetnessEngine.evaluate(
                route: route,
                departure: TestSupport.date(hour: 10),
                paceFactor: 1.0,
                threshold: 0,
                forecasts: forecasts
            )
        ) { error in
            XCTAssertEqual(error as? WetnessError, WetnessError.invalidThreshold)
        }
    }

    func testFullyWetAndFullyDryRounding() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let wetForecast = TestSupport.hourlyForecast(startHour: 11, values: [(1.0, 1.0)])
        let dryForecast = TestSupport.hourlyForecast(startHour: 11, values: [(0.0, 0.0)])

        let wet = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: try TestSupport.uniformForecasts(route: route, forecast: wetForecast)
        )
        let dry = try WetnessEngine.evaluate(
            route: route,
            departure: TestSupport.date(hour: 10),
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: try TestSupport.uniformForecasts(route: route, forecast: dryForecast)
        )

        XCTAssertEqual(wet.roundedWetPercent, 100)
        XCTAssertEqual(dry.roundedWetPercent, 0)
    }
}
