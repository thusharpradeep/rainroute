import XCTest
@testable import RainRoute

final class RouteLinksTests: XCTestCase {
    private let start = GeoCoordinate(latitude: 10.0, longitude: 76.0)
    private let firstStop = GeoCoordinate(latitude: 10.1, longitude: 76.1)
    private let secondStop = GeoCoordinate(latitude: 10.2, longitude: 76.2)
    private let destination = GeoCoordinate(latitude: 10.3, longitude: 76.3)

    func testGoogleMapsWebURLIncludesOrderedWaypoints() throws {
        let url = RouteLinks.googleMaps(
            start: start,
            destination: destination,
            waypoints: [firstStop, secondStop]
        )

        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(url.path, "/maps/dir/")

        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let values = Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(values["api"], "1")
        XCTAssertEqual(values["origin"], "10.000000,76.000000")
        XCTAssertEqual(values["destination"], "10.300000,76.300000")
        XCTAssertEqual(
            values["waypoints"],
            "10.100000,76.100000|10.200000,76.200000"
        )
        XCTAssertEqual(values["travelmode"], "driving")
    }

    func testGoogleMapsWebURLOmitsWaypointsWhenThereAreNone() throws {
        let url = RouteLinks.googleMaps(
            start: start,
            destination: destination,
            waypoints: []
        )
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )

        XCTAssertFalse(items.contains { $0.name == "waypoints" })
    }

    func testGoogleMapsAppURLCarriesWaypointsAndDrivingMode() throws {
        let url = try XCTUnwrap(
            RouteLinks.googleMapsApp(
                start: start,
                destination: destination,
                waypoints: [firstStop]
            )
        )

        XCTAssertEqual(url.scheme, "comgooglemaps")
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let values = Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(values["saddr"], "10.000000,76.000000")
        XCTAssertEqual(values["daddr"], "10.300000,76.300000")
        XCTAssertEqual(values["waypoints"], "10.100000,76.100000")
        XCTAssertEqual(values["directionsmode"], "driving")
    }

    func testAppleMapsURLUsesStartAndDestinationOnly() throws {
        let url = RouteLinks.appleMaps(start: start, destination: destination)

        XCTAssertEqual(url.host, "maps.apple.com")
        let items = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let values = Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }
        )

        XCTAssertEqual(values["saddr"], "10.000000,76.000000")
        XCTAssertEqual(values["daddr"], "10.300000,76.300000")
        XCTAssertEqual(values["dirflg"], "d")
        XCTAssertFalse(items.contains { $0.name == "waypoints" })
    }
}
