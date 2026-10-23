import XCTest
@testable import RainRoute

final class HourlyForecastTests: XCTestCase {
    private var forecast: HourlyForecast {
        HourlyForecast(hours: [
            .init(time: TestSupport.date(hour: 12), precipitationMM: 0.1),
            .init(time: TestSupport.date(hour: 13), precipitationMM: 0.2),
            .init(time: TestSupport.date(hour: 14), precipitationMM: 0.3),
            .init(time: TestSupport.date(hour: 15), precipitationMM: 0.4),
            .init(time: TestSupport.date(hour: 16), precipitationMM: 0.5)
        ])
    }

    func testEtaInsideAnHourUsesTheBucketThatEndsAtTheNextHour() {
        let hour = forecast.hour(containing: TestSupport.date(hour: 14, minute: 37))
        XCTAssertEqual(hour?.time, TestSupport.date(hour: 15))
        XCTAssertEqual(hour?.precipitationMM, 0.4)
    }

    func testEtaExactlyOnTheHourUsesThatHour() {
        XCTAssertEqual(
            forecast.hour(containing: TestSupport.date(hour: 15))?.time,
            TestSupport.date(hour: 15)
        )
    }

    func testEtaOneMinuteAfterTheHourUsesTheNextBucket() {
        XCTAssertEqual(
            forecast.hour(containing: TestSupport.date(hour: 15, minute: 1))?.time,
            TestSupport.date(hour: 16)
        )
    }

    func testEtaExactlyAtTheLastBucketIsValid() {
        XCTAssertEqual(
            forecast.hour(containing: TestSupport.date(hour: 16))?.time,
            TestSupport.date(hour: 16)
        )
    }

    func testEtaAfterTheLastBucketIsMissing() {
        XCTAssertNil(forecast.hour(containing: TestSupport.date(hour: 16, minute: 1)))
    }

    func testEtaBeforeTheForecastWindowIsMissing() {
        XCTAssertNil(forecast.hour(containing: TestSupport.date(hour: 10, minute: 59)))
    }

    func testEtaAtTheStartOfTheFirstBucketIsValid() {
        XCTAssertEqual(
            forecast.hour(containing: TestSupport.date(hour: 11))?.time,
            TestSupport.date(hour: 12)
        )
    }

    func testProbabilityIsClampedToUnitInterval() {
        let hour = HourlyForecast.Hour(
            time: TestSupport.date(hour: 12),
            precipitationMM: 1,
            probability: 1.7
        )
        XCTAssertEqual(hour.probability, 1.0)

        let negative = HourlyForecast.Hour(
            time: TestSupport.date(hour: 12),
            precipitationMM: 1,
            probability: -0.4
        )
        XCTAssertEqual(negative.probability, 0.0)
    }

    func testHoursAreSortedByTime() {
        let unsorted = HourlyForecast(hours: [
            .init(time: TestSupport.date(hour: 14), precipitationMM: 1),
            .init(time: TestSupport.date(hour: 12), precipitationMM: 2),
            .init(time: TestSupport.date(hour: 13), precipitationMM: 3)
        ])
        XCTAssertEqual(unsorted.hours.map(\.time), [
            TestSupport.date(hour: 12),
            TestSupport.date(hour: 13),
            TestSupport.date(hour: 14)
        ])
    }
}
