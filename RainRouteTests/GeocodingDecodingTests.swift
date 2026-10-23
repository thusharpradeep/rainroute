import XCTest
@testable import RainRoute

final class GeocodingDecodingTests: XCTestCase {
    private let tirurJSON = """
    {
      "features": [
        {
          "type": "Feature",
          "properties": {
            "osm_type": "N",
            "osm_id": 344437127,
            "name": "Tirur",
            "county": "Tirur",
            "state": "Kerala",
            "country": "India",
            "postcode": "676101",
            "countrycode": "IN"
          },
          "geometry": {
            "type": "Point",
            "coordinates": [75.923986, 10.9166828]
          }
        }
      ]
    }
    """

    func testDecodesPhotonPlaceAndBuildsDisplayName() throws {
        let places = try PhotonGeocoder.decodePlaces(from: Data(tirurJSON.utf8))

        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "Tirur")
        XCTAssertEqual(places[0].displayName, "Tirur, Kerala, India")
        XCTAssertEqual(places[0].coordinate.latitude, 10.9166828, accuracy: 0.0000001)
        XCTAssertEqual(places[0].coordinate.longitude, 75.923986, accuracy: 0.0000001)
    }

    func testBuildsNameFromStreetWhenANameIsMissing() throws {
        let json = """
        {
          "features": [
            {
              "properties": {
                "osm_type": "W",
                "osm_id": 42,
                "street": "MG Road",
                "housenumber": "12",
                "city": "Kochi",
                "state": "Kerala",
                "country": "India"
              },
              "geometry": { "type": "Point", "coordinates": [76.27, 9.97] }
            }
          ]
        }
        """
        let places = try PhotonGeocoder.decodePlaces(from: Data(json.utf8))
        XCTAssertEqual(places.first?.name, "12 MG Road")
        XCTAssertEqual(places.first?.subtitle, "Kochi, Kerala, India")
    }

    func testDeduplicatesIdenticalFeatures() throws {
        let json = """
        {
          "features": [
            {
              "properties": { "osm_type": "N", "osm_id": 1, "name": "A", "state": "Kerala", "country": "India" },
              "geometry": { "type": "Point", "coordinates": [76.0, 10.0] }
            },
            {
              "properties": { "osm_type": "N", "osm_id": 1, "name": "A", "state": "Kerala", "country": "India" },
              "geometry": { "type": "Point", "coordinates": [76.0, 10.0] }
            }
          ]
        }
        """
        let places = try PhotonGeocoder.decodePlaces(from: Data(json.utf8))
        XCTAssertEqual(places.count, 1)
    }

    func testRejectsInvalidCoordinates() throws {
        let json = """
        {
          "features": [
            {
              "properties": { "name": "Bad" },
              "geometry": { "type": "Point", "coordinates": [200.0, 100.0] }
            }
          ]
        }
        """
        let places = try PhotonGeocoder.decodePlaces(from: Data(json.utf8))
        XCTAssertTrue(places.isEmpty)
    }

    func testInvalidJSONThrowsDecodingError() {
        XCTAssertThrowsError(
            try PhotonGeocoder.decodePlaces(from: Data("not json".utf8))
        ) { error in
            guard let apiError = error as? APIError,
                  case .decoding = apiError else {
                return XCTFail("Expected APIError.decoding, got \(error)")
            }
        }
    }
}
