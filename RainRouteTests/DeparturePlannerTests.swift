import XCTest
@testable import RainRoute

final class DeparturePlannerTests: XCTestCase {
    func testPlannerFindsTheDryWindowForTirurKochiFixture() throws {
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
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1),
                (0.0, 0.1)
            ]
        )
        let forecasts = try TestSupport.uniformForecasts(
            route: route,
            forecast: forecast,
            segmentCount: 13
        )
        let now = TestSupport.date(hour: 10)

        let plan = try DeparturePlanner.plan(
            route: route,
            now: now,
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            segmentCount: 13
        )

        XCTAssertTrue(plan.shouldWait)
        XCTAssertEqual(plan.now.wetSegmentCount, 11)
        XCTAssertEqual(plan.best.wetSegmentCount, 0)
        XCTAssertEqual(plan.segmentsSaved, 11)
        XCTAssertEqual(plan.bestDeparture, TestSupport.date(hour: 12))
        XCTAssertEqual(plan.best.probabilityWeightedShare ?? -1, 0.1, accuracy: 0.0001)

        let direct = try WetnessEngine.evaluate(
            route: route,
            departure: plan.bestDeparture,
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            segmentCount: 13
        )
        XCTAssertEqual(plan.best, direct)
    }

    func testPlannerSaysLeaveNowWhenNoSegmentsAreSaved() throws {
        let route = TestSupport.simpleRoute()
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [(0.0, 0.1), (0.0, 0.1), (0.0, 0.1), (0.0, 0.1)]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let now = TestSupport.date(hour: 10)

        let plan = try DeparturePlanner.plan(
            route: route,
            now: now,
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        XCTAssertFalse(plan.shouldWait)
        XCTAssertEqual(plan.bestDeparture, now)
        XCTAssertEqual(plan.segmentsSaved, 0)
        XCTAssertEqual(plan.best, plan.now)
    }

    func testProbabilityBreaksTiesBetweenEqualWetCounts() throws {
        let route = TestSupport.simpleRoute(totalMeters: 30_000, durationSeconds: 3_600)
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [
                (0.0, 0.1),
                (0.6, 0.9),
                (0.0, 0.8),
                (0.0, 0.2),
                (0.0, 0.2),
                (0.0, 0.2),
                (0.0, 0.2)
            ]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let now = TestSupport.date(hour: 10)

        let plan = try DeparturePlanner.plan(
            route: route,
            now: now,
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts,
            window: 4 * 60 * 60,
            step: 60 * 60
        )

        XCTAssertTrue(plan.shouldWait)
        XCTAssertEqual(plan.now.wetSegmentCount, 12)
        XCTAssertEqual(plan.best.wetSegmentCount, 0)
        XCTAssertEqual(plan.segmentsSaved, 12)
        XCTAssertEqual(plan.bestDeparture, TestSupport.date(hour: 12))
        XCTAssertEqual(plan.best.probabilityWeightedShare ?? -1, 0.2, accuracy: 0.0001)
    }

    func testBestDepartureIsOnTheFifteenMinuteGrid() throws {
        let route = TestSupport.tirurKochiRoute()
        let forecast = TestSupport.hourlyForecast(
            startHour: 10,
            values: [
                (0.6, 0.8), (0.6, 0.8), (0.0, 0.1), (0.0, 0.1),
                (0.0, 0.1), (0.0, 0.1), (0.0, 0.1), (0.0, 0.1)
            ]
        )
        let forecasts = try TestSupport.uniformForecasts(route: route, forecast: forecast)
        let now = TestSupport.date(hour: 10)
        let plan = try DeparturePlanner.plan(
            route: route,
            now: now,
            paceFactor: 1.0,
            threshold: 0.2,
            forecasts: forecasts
        )

        let offset = plan.bestDeparture.timeIntervalSince(now)
        XCTAssertEqual(offset.truncatingRemainder(dividingBy: 900), 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(offset, 4 * 60 * 60)
    }

    func testPlannerThrowsWhenNowHasNoForecast() {
        XCTAssertThrowsError(
            try DeparturePlanner.plan(
                route: TestSupport.simpleRoute(),
                now: TestSupport.date(hour: 10),
                paceFactor: 1.0,
                threshold: 0.2,
                forecasts: [:]
            )
        )
    }
}
