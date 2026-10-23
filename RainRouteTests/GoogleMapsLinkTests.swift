import XCTest
@testable import RainRoute

final class GoogleMapsLinkTests: XCTestCase {
    func testParsesQueryDirectionsLink() throws {
        let url = URL(string: "https://www.google.com/maps/dir/?api=1&origin=Tirur%2C+Kerala&destination=Kochi%2C+Kerala&waypoints=Thrissur%2C+Kerala%7CAluva&travelmode=driving")!
        let link = try GoogleMapsLinkParser.parse(url)

        XCTAssertEqual(link.origin.text, "Tirur, Kerala")
        XCTAssertEqual(link.waypoints.map(\.text), ["Thrissur, Kerala", "Aluva"])
        XCTAssertEqual(link.destination.text, "Kochi, Kerala")
        XCTAssertNil(link.origin.coordinate)
    }

    func testParsesPathDirectionsLinkAndIgnoresMapState() throws {
        let url = URL(string: "https://www.google.co.in/maps/dir/Tirur,+Kerala/Thrissur,+Kerala/Kochi,+Kerala/@10.5,76.2,9z/data=!4m2!4m1!3e0")!
        let link = try GoogleMapsLinkParser.parse(url)

        XCTAssertEqual(link.origin.text, "Tirur, Kerala")
        XCTAssertEqual(link.waypoints.map(\.text), ["Thrissur, Kerala"])
        XCTAssertEqual(link.destination.text, "Kochi, Kerala")
    }

    func testParsesCoordinateStops() throws {
        let url = URL(string: "https://www.google.com/maps/dir/10.9,75.9/10.5,76.2/9.9,76.3")!
        let link = try GoogleMapsLinkParser.parse(url)

        XCTAssertEqual(
            link.origin.coordinate,
            GeoCoordinate(latitude: 10.9, longitude: 75.9)
        )
        XCTAssertEqual(
            link.waypoints.first?.coordinate,
            GeoCoordinate(latitude: 10.5, longitude: 76.2)
        )
        XCTAssertEqual(
            link.destination.coordinate,
            GeoCoordinate(latitude: 9.9, longitude: 76.3)
        )
    }

    func testDecodesPercentEscapesAndPlusSigns() throws {
        let url = URL(string: "https://www.google.com/maps/dir/St.+Mary%27s+Church/Ernakulam+Junction")!
        let link = try GoogleMapsLinkParser.parse(url)

        XCTAssertEqual(link.origin.text, "St. Mary's Church")
        XCTAssertEqual(link.destination.text, "Ernakulam Junction")
    }

    func testRejectsWalkingLinks() {
        let url = URL(string: "https://www.google.com/maps/dir/A/B?travelmode=walking")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleMapsLinkError, .unsupportedTravelMode("walking"))
        }
    }

    func testRejectsShortLinksUntilTheyAreResolved() {
        let url = URL(string: "https://maps.app.goo.gl/abc123")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleMapsLinkError, .needsResolution)
        }
    }

    func testRejectsMissingOrigin() {
        let url = URL(string: "https://www.google.com/maps/dir//Kochi,+Kerala")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleMapsLinkError, .missingOrigin)
        }
    }

    func testRejectsTooManyWaypoints() {
        let waypoints = (1...10).map { "Stop\($0)" }.joined(separator: "%7C")
        let url = URL(string: "https://www.google.com/maps/dir/?api=1&origin=A&destination=B&waypoints=\(waypoints)")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            guard case .tooManyWaypoints(let count) = error as? GoogleMapsLinkError else {
                return XCTFail("Expected tooManyWaypoints, got \(error)")
            }
            XCTAssertEqual(count, 10)
        }
    }

    func testRejectsSameEndpoints() {
        let url = URL(string: "https://www.google.com/maps/dir/10.5,76.2/10.5,76.2")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleMapsLinkError, .sameEndpoints)
        }
    }

    func testRejectsNonGoogleHosts() {
        let url = URL(string: "https://example.com/maps/dir/A/B")!
        XCTAssertThrowsError(try GoogleMapsLinkParser.parse(url)) { error in
            XCTAssertEqual(error as? GoogleMapsLinkError, .notGoogleMaps)
        }
    }
}
