import XCTest
@testable import RainRoute

final class WeatherDecodingTests: XCTestCase {
    private let cellA = GridCell(latitudeTenths: 109, longitudeTenths: 759)
    private let cellB = GridCell(latitudeTenths: 99, longitudeTenths: 763)

    func testDecodesSingleLocationHourlyForecast() throws {
        let json = """
        {
          "hourly": {
            "time": [1761300000, 1761303600, 1761307200],
            "precipitation": [0.2, null, 0.0],
            "precipitation_probability": [86, 79, 72]
          }
        }
        """
        let result = try OpenMeteoWeatherService.decodeForecasts(
            from: Data(json.utf8),
            cells: [cellA]
        )
        let forecast = try XCTUnwrap(result[cellA])

        XCTAssertEqual(forecast.hours.count, 2)
        XCTAssertEqual(forecast.hours[0].precipitationMM, 0.2, accuracy: 0.0001)
        XCTAssertEqual(forecast.hours[0].probability ?? -1, 0.86, accuracy: 0.0001)
        XCTAssertEqual(forecast.hours[1].precipitationMM, 0.0, accuracy: 0.0001)
        XCTAssertEqual(forecast.hours[1].probability ?? -1, 0.72, accuracy: 0.0001)
    }

    func testDecodesMultipleLocationsInOrder() throws {
        let json = """
        [
          {
            "hourly": {
              "time": [1761300000],
              "precipitation": [0.4],
              "precipitation_probability": [50]
            }
          },
          {
            "hourly": {
              "time": [1761300000],
              "precipitation": [0.0],
              "precipitation_probability": [10]
            }
          }
        ]
        """
        let result = try OpenMeteoWeatherService.decodeForecasts(
            from: Data(json.utf8),
            cells: [cellA, cellB]
        )

        XCTAssertEqual(result[cellA]?.hours.first?.precipitationMM, 0.4)
        XCTAssertEqual(result[cellB]?.hours.first?.precipitationMM, 0.0)
    }

    func testHandlesMissingProbabilityArray() throws {
        let json = """
        {
          "hourly": {
            "time": [1761300000],
            "precipitation": [0.4]
          }
        }
        """
        let result = try OpenMeteoWeatherService.decodeForecasts(
            from: Data(json.utf8),
            cells: [cellA]
        )
        XCTAssertNil(result[cellA]?.hours.first?.probability)
    }

    func testErrorResponseThrowsServiceError() {
        let json = """
        {"error": true, "reason": "Latitude must be in range"}
        """
        XCTAssertThrowsError(
            try OpenMeteoWeatherService.decodeForecasts(
                from: Data(json.utf8),
                cells: [cellA]
            )
        ) { error in
            XCTAssertEqual(
                error as? APIError,
                APIError.service("Latitude must be in range")
            )
        }
    }

    func testCellCountMismatchThrowsIncompleteForecast() {
        let json = """
        [{"hourly":{"time":[1761300000],"precipitation":[0.0]}}]
        """
        XCTAssertThrowsError(
            try OpenMeteoWeatherService.decodeForecasts(
                from: Data(json.utf8),
                cells: [cellA, cellB]
            )
        ) { error in
            XCTAssertEqual(error as? APIError, APIError.incompleteForecast)
        }
    }

    func testEmptyHourlyDataThrowsDecodingError() {
        let json = """
        {"hourly":{"time":[],"precipitation":[]}}
        """
        XCTAssertThrowsError(
            try OpenMeteoWeatherService.decodeForecasts(
                from: Data(json.utf8),
                cells: [cellA]
            )
        ) { error in
            guard let apiError = error as? APIError,
                  case .decoding = apiError else {
                return XCTFail("Expected APIError.decoding, got \(error)")
            }
        }
    }
}
