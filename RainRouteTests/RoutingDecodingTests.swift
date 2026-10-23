import XCTest
@testable import RainRoute

final class RoutingDecodingTests: XCTestCase {
    func testDecodesRouteWithAnnotations() throws {
        let json = """
        {
          "code": "Ok",
          "routes": [
            {
              "distance": 1000,
              "duration": 120,
              "geometry": {
                "coordinates": [[76.0, 10.0], [76.01, 10.0], [76.02, 10.0]]
              },
              "legs": [
                {
                  "annotation": {
                    "distance": [500, 500],
                    "duration": [60, 60]
                  }
                }
              ]
            }
          ]
        }
        """
        let route = try OSRMRouter.decodeRoute(from: Data(json.utf8))

        XCTAssertEqual(route.coordinates.count, 3)
        XCTAssertEqual(route.totalDistanceMeters, 1000, accuracy: 0.001)
        XCTAssertEqual(route.totalDurationSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDistances, [0, 500, 1000])
        XCTAssertEqual(route.cumulativeDurations, [0, 60, 120])
        XCTAssertEqual(route.coordinates[0].latitude, 10.0, accuracy: 0.000001)
        XCTAssertEqual(route.coordinates[0].longitude, 76.0, accuracy: 0.000001)
    }

    func testScalesAnnotationProfileToRouteTotals() throws {
        let json = """
        {
          "code": "Ok",
          "routes": [
            {
              "distance": 1000,
              "duration": 130,
              "geometry": {
                "coordinates": [[76.0, 10.0], [76.01, 10.0], [76.02, 10.0]]
              },
              "legs": [
                {
                  "annotation": {
                    "distance": [500, 500],
                    "duration": [60, 60]
                  }
                }
              ]
            }
          ]
        }
        """
        let route = try OSRMRouter.decodeRoute(from: Data(json.utf8))
        XCTAssertEqual(route.totalDurationSeconds, 130, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDurations[1], 65, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDurations[2], 130, accuracy: 0.001)
    }

    func testFallsBackToConstantSpeedWithoutAnnotations() throws {
        let json = """
        {
          "code": "Ok",
          "routes": [
            {
              "distance": 1000,
              "duration": 120,
              "geometry": {
                "coordinates": [[76.0, 10.0], [76.01, 10.0], [76.02, 10.0]]
              },
              "legs": [
                {
                  "steps": []
                }
              ]
            }
          ]
        }
        """
        let route = try OSRMRouter.decodeRoute(from: Data(json.utf8))
        XCTAssertEqual(route.totalDistanceMeters, 1000, accuracy: 0.001)
        XCTAssertEqual(route.totalDurationSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDistances.last ?? -1, 1000, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDurations[1], 60, accuracy: 2)
    }

    func testMergesAnnotationsAcrossMultipleLegs() throws {
        let json = """
        {
          "code": "Ok",
          "routes": [
            {
              "distance": 1000,
              "duration": 120,
              "geometry": {
                "coordinates": [[76.0, 10.0], [76.01, 10.0], [76.02, 10.0]]
              },
              "legs": [
                {"annotation": {"distance": [500], "duration": [60]}},
                {"annotation": {"distance": [500], "duration": [60]}}
              ]
            }
          ]
        }
        """
        let route = try OSRMRouter.decodeRoute(from: Data(json.utf8))

        XCTAssertEqual(route.cumulativeDistances, [0, 500, 1000])
        XCTAssertEqual(route.cumulativeDurations, [0, 60, 120])
    }

    func testFallsBackWhenMergedAnnotationsDoNotMatchGeometry() throws {
        let json = """
        {
          "code": "Ok",
          "routes": [
            {
              "distance": 1000,
              "duration": 120,
              "geometry": {
                "coordinates": [[76.0, 10.0], [76.01, 10.0], [76.02, 10.0]]
              },
              "legs": [
                {"annotation": {"distance": [1000], "duration": [120]}}
              ]
            }
          ]
        }
        """
        let route = try OSRMRouter.decodeRoute(from: Data(json.utf8))

        XCTAssertEqual(route.cumulativeDistances.last ?? -1, 1000, accuracy: 0.001)
        XCTAssertEqual(route.cumulativeDurations[1], 60, accuracy: 2)
        XCTAssertEqual(route.cumulativeDurations.last ?? -1, 120, accuracy: 0.001)
    }

    func testRouteURLJoinsAnchorsInOrder() throws {
        let url = try XCTUnwrap(
            OSRMRouter.routeURL(
                baseURL: URL(string: "https://router.project-osrm.org")!,
                coordinates: [
                    GeoCoordinate(latitude: 10.0, longitude: 76.0),
                    GeoCoordinate(latitude: 10.1, longitude: 76.1),
                    GeoCoordinate(latitude: 10.2, longitude: 76.2)
                ],
                annotations: true
            )
        )

        XCTAssertEqual(
            url.path,
            "/route/v1/driving/76.0,10.0;76.1,10.1;76.2,10.2"
        )
        XCTAssertTrue(url.query?.contains("overview=full") == true)
        XCTAssertTrue(url.query?.contains("annotations=duration,distance") == true)
    }

    func testRejectsFewerThanTwoAnchorsBeforeNetworking() async {
        let router = OSRMRouter()
        do {
            _ = try await router.route(
                through: [GeoCoordinate(latitude: 10, longitude: 76)]
            )
            XCTFail("Expected a service error")
        } catch let error as APIError {
            XCTAssertEqual(error, .service("A route needs at least two points."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoRouteResponseThrowsServiceError() {
        let json = """
        {"code": "NoRoute", "message": "No route found"}
        """
        XCTAssertThrowsError(
            try OSRMRouter.decodeRoute(from: Data(json.utf8))
        ) { error in
            XCTAssertEqual(error as? APIError, APIError.service("No route found"))
        }
    }

    func testMalformedRoutingJSONThrowsDecodingError() {
        XCTAssertThrowsError(
            try OSRMRouter.decodeRoute(from: Data("{}".utf8))
        ) { error in
            guard let apiError = error as? APIError,
                  case .decoding = apiError else {
                return XCTFail("Expected APIError.decoding, got \(error)")
            }
        }
    }
}
