import XCTest
@testable import RainRoute

private struct FakeLinkResolver: GoogleMapsLinkResolving {
    let resolved: URL

    func resolve(_ url: URL) async throws -> URL {
        resolved
    }
}

private final class FakeGeocoder: PlaceSearching {
    let results: [String: [Place]]
    private(set) var queries: [String] = []

    init(results: [String: [Place]]) {
        self.results = results
    }

    func search(_ query: String) async throws -> [Place] {
        queries.append(query)
        return results[query] ?? []
    }
}

final class GoogleMapsImporterTests: XCTestCase {
    private func place(_ name: String, latitude: Double, longitude: Double) -> Place {
        Place(
            id: name,
            name: name,
            subtitle: nil,
            coordinate: GeoCoordinate(latitude: latitude, longitude: longitude)
        )
    }

    func testImportsExpandedLinkAndGeocodesPlaceNames() async throws {
        let expanded = URL(string: "https://www.google.com/maps/dir/Tirur/Thrissur/Kochi")!
        let geocoder = FakeGeocoder(results: [
            "Tirur": [place("Tirur", latitude: 10.9, longitude: 75.9)],
            "Thrissur": [place("Thrissur", latitude: 10.5, longitude: 76.2)],
            "Kochi": [place("Kochi", latitude: 9.9, longitude: 76.3)]
        ])
        let importer = GoogleMapsRouteImporter(
            resolver: FakeLinkResolver(resolved: expanded),
            geocoder: geocoder
        )

        let imported = try await importer.importRoute(
            from: "https://maps.app.goo.gl/abc123"
        )

        XCTAssertEqual(imported.origin.name, "Tirur")
        XCTAssertEqual(imported.waypoints.map(\.name), ["Thrissur"])
        XCTAssertEqual(imported.destination.name, "Kochi")
        XCTAssertEqual(geocoder.queries, ["Tirur", "Thrissur", "Kochi"])
    }

    func testCoordinateStopsDoNotCallTheGeocoder() async throws {
        let expanded = URL(string: "https://www.google.com/maps/dir/10.9,75.9/10.5,76.2/9.9,76.3")!
        let geocoder = FakeGeocoder(results: [:])
        let importer = GoogleMapsRouteImporter(
            resolver: FakeLinkResolver(resolved: expanded),
            geocoder: geocoder
        )

        let imported = try await importer.importRoute(from: expanded.absoluteString)

        XCTAssertTrue(geocoder.queries.isEmpty)
        XCTAssertEqual(imported.origin.coordinate, GeoCoordinate(latitude: 10.9, longitude: 75.9))
        XCTAssertEqual(imported.waypoints.first?.coordinate, GeoCoordinate(latitude: 10.5, longitude: 76.2))
        XCTAssertEqual(imported.destination.coordinate, GeoCoordinate(latitude: 9.9, longitude: 76.3))
    }

    func testReportsAnUnresolvedPlaceName() async throws {
        let expanded = URL(string: "https://www.google.com/maps/dir/Nowhere/Somewhere")!
        let importer = GoogleMapsRouteImporter(
            resolver: FakeLinkResolver(resolved: expanded),
            geocoder: FakeGeocoder(results: [:])
        )

        do {
            _ = try await importer.importRoute(from: expanded.absoluteString)
            XCTFail("Expected placeNotFound")
        } catch let error as GoogleMapsLinkError {
            XCTAssertEqual(error, .placeNotFound("Nowhere"))
        }
    }

    func testRemovesConsecutiveDuplicateAnchors() async throws {
        let expanded = URL(string: "https://www.google.com/maps/dir/10.0,76.0/10.0,76.0001/11.0,77.0")!
        let importer = GoogleMapsRouteImporter(
            resolver: FakeLinkResolver(resolved: expanded),
            geocoder: FakeGeocoder(results: [:])
        )

        let imported = try await importer.importRoute(from: expanded.absoluteString)

        XCTAssertTrue(imported.waypoints.isEmpty)
        XCTAssertEqual(imported.origin.coordinate, GeoCoordinate(latitude: 10.0, longitude: 76.0))
        XCTAssertEqual(imported.destination.coordinate, GeoCoordinate(latitude: 11.0, longitude: 77.0))
    }

    func testAddsHTTPSWhenThePastedLinkHasNoScheme() async throws {
        let expanded = URL(string: "https://www.google.com/maps/dir/10.0,76.0/11.0,77.0")!
        let importer = GoogleMapsRouteImporter(
            resolver: FakeLinkResolver(resolved: expanded),
            geocoder: FakeGeocoder(results: [:])
        )

        let imported = try await importer.importRoute(
            from: "www.google.com/maps/dir/10.0,76.0/11.0,77.0"
        )
        XCTAssertEqual(imported.destination.coordinate, GeoCoordinate(latitude: 11.0, longitude: 77.0))
    }
}
