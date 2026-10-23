import Foundation

struct Place: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String?
    let coordinate: GeoCoordinate

    var displayName: String {
        guard let subtitle, !subtitle.isEmpty else { return name }
        return "\(name), \(subtitle)"
    }
}

struct PhotonGeocoder: Sendable {
    var baseURL: URL = URL(string: "https://photon.komoot.io/api/")!
    var session: URLSession = .shared

    func search(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "lang", value: "en")
        ]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let data = try await HTTP.data(
            for: HTTP.request(url: url),
            session: session
        )
        return try Self.decodePlaces(from: data)
    }

    static func decodePlaces(from data: Data) throws -> [Place] {
        let response: PhotonResponse
        do {
            response = try JSONDecoder().decode(PhotonResponse.self, from: data)
        } catch {
            throw APIError.decoding("place search response")
        }
        return places(from: response.features)
    }

    static func places(from features: [PhotonFeature]) -> [Place] {
        var seen = Set<String>()
        var places: [Place] = []

        for feature in features {
            guard feature.geometry.coordinates.count >= 2 else { continue }
            let longitude = feature.geometry.coordinates[0]
            let latitude = feature.geometry.coordinates[1]
            guard latitude.isFinite, longitude.isFinite,
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude) else {
                continue
            }

            let properties = feature.properties
            let name = firstNonEmpty(
                properties.name,
                joinedStreet(properties),
                properties.city,
                properties.county,
                properties.state
            ) ?? "Unnamed place"

            let subtitle = subtitle(for: properties, name: name)
            let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
            let id = [
                properties.osmType ?? "x",
                String(properties.osmID ?? 0),
                String(format: "%.5f", latitude),
                String(format: "%.5f", longitude)
            ].joined(separator: "-")

            guard seen.insert(id).inserted else { continue }
            places.append(
                Place(
                    id: id,
                    name: name,
                    subtitle: subtitle,
                    coordinate: coordinate
                )
            )
        }

        return places
    }

    private static func subtitle(
        for properties: PhotonFeature.Properties,
        name: String
    ) -> String? {
        var parts: [String] = []

        if let city = firstNonEmpty(properties.city),
           city != name,
           !parts.contains(city) {
            parts.append(city)
        } else if let county = firstNonEmpty(properties.county),
                  county != name,
                  !parts.contains(county) {
            parts.append(county)
        }

        if let state = firstNonEmpty(properties.state),
           state != name,
           !parts.contains(state) {
            parts.append(state)
        }

        if let country = firstNonEmpty(properties.country),
           !parts.contains(country) {
            parts.append(country)
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func joinedStreet(_ properties: PhotonFeature.Properties) -> String? {
        let street = firstNonEmpty(properties.street)
        let number = firstNonEmpty(properties.housenumber)
        if let number = number, let street = street {
            return "\(number) \(street)"
        }
        if let street = street {
            return street
        }
        return number
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}

struct PhotonResponse: Decodable {
    let features: [PhotonFeature]
}

struct PhotonFeature: Decodable {
    let geometry: Geometry
    let properties: Properties

    struct Geometry: Decodable {
        let coordinates: [Double]
    }

    struct Properties: Decodable {
        let osmType: String?
        let osmID: Int?
        let name: String?
        let street: String?
        let housenumber: String?
        let city: String?
        let county: String?
        let state: String?
        let country: String?
        let postcode: String?

        enum CodingKeys: String, CodingKey {
            case osmType = "osm_type"
            case osmID = "osm_id"
            case name
            case street
            case housenumber
            case city
            case county
            case state
            case country
            case postcode
        }
    }
}
