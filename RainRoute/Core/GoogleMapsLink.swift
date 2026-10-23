import Foundation

struct GoogleMapsStop: Equatable, Sendable {
    /// The decoded place name or coordinate text from the link.
    let text: String
    /// Present when the stop was already a `lat,lng` pair.
    let coordinate: GeoCoordinate?

    init(text: String, coordinate: GeoCoordinate? = nil) {
        self.text = text
        self.coordinate = coordinate
    }
}

struct GoogleMapsRouteLink: Equatable, Sendable {
    let origin: GoogleMapsStop
    let waypoints: [GoogleMapsStop]
    let destination: GoogleMapsStop

    var stops: [GoogleMapsStop] {
        [origin] + waypoints + [destination]
    }
}

enum GoogleMapsLinkError: LocalizedError, Equatable {
    case invalidLink
    case notGoogleMaps
    case needsResolution
    case unsupportedScheme
    case missingOrigin
    case noStops
    case tooManyWaypoints(Int)
    case unsupportedTravelMode(String)
    case sameEndpoints
    case placeNotFound(String)
    case resolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            return "Paste a Google Maps directions link."
        case .notGoogleMaps:
            return "That is not a Google Maps link. Open Google Maps, choose directions, tap Share, then Copy link."
        case .needsResolution:
            return "RainRoute could not expand that shortened Google Maps link. Open it in Safari, then copy the full google.com/maps URL and paste that instead."
        case .unsupportedScheme:
            return "Paste an http:// or https:// Google Maps link."
        case .missingOrigin:
            return "This link has no start. Set a start in Google Maps, then share the route again."
        case .noStops:
            return "This Google Maps link does not contain a route. Choose directions in Google Maps and share the route."
        case .tooManyWaypoints(let count):
            return "Google Maps links can include up to 9 stops. This link has \(count) stops between the start and destination."
        case .unsupportedTravelMode(let mode):
            return "RainRoute imports driving routes only. This link is for \(mode)."
        case .sameEndpoints:
            return "The start and destination in that link are the same place."
        case .placeNotFound(let name):
            return "RainRoute could not find “\(name)” from the link. Try a more specific place in Google Maps and share again."
        case .resolutionFailed(let detail):
            return "RainRoute could not read the Google Maps link. \(detail)"
        }
    }
}

enum GoogleMapsLinkParser {
    static let maximumWaypoints = 9

    static func parse(_ url: URL) throws -> GoogleMapsRouteLink {
        guard let scheme = url.scheme?.lowercased() else {
            throw GoogleMapsLinkError.invalidLink
        }
        guard scheme == "http" || scheme == "https" else {
            throw GoogleMapsLinkError.unsupportedScheme
        }
        if isShortLink(url) {
            throw GoogleMapsLinkError.needsResolution
        }
        guard isGoogleMapsURL(url) else {
            throw GoogleMapsLinkError.notGoogleMaps
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let query = Dictionary(
            queryItems.map { ($0.name.lowercased(), $0.value ?? "") },
            uniquingKeysWith: { _, latest in latest }
        )

        try validateTravelMode(
            travelMode: query["travelmode"],
            directionFlag: query["dirflg"]
        )

        if query["origin"] != nil
            || query["destination"] != nil
            || query["saddr"] != nil
            || query["daddr"] != nil {
            return try parseQueryRoute(query)
        }

        return try parsePathRoute(url)
    }

    static func isGoogleMapsURL(_ url: URL) -> Bool {
        guard let host = normalizedHost(url) else { return false }
        return host == "google.com"
            || host.hasSuffix(".google.com")
            || host.hasPrefix("google.")
            || host.contains(".google.")
    }

    static func isShortLink(_ url: URL) -> Bool {
        guard let host = normalizedHost(url) else { return false }
        return host == "maps.app.goo.gl" || host == "goo.gl"
    }

    static func coordinate(from text: String) -> GeoCoordinate? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let latitudeText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeText = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude = Double(latitudeText),
              let longitude = Double(longitudeText),
              latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        return GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host.isEmpty ? nil : host
    }

    private static func parseQueryRoute(
        _ query: [String: String]
    ) throws -> GoogleMapsRouteLink {
        let originText = (query["origin"] ?? query["saddr"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destinationText = (query["destination"] ?? query["daddr"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !originText.isEmpty else {
            throw GoogleMapsLinkError.missingOrigin
        }
        guard !destinationText.isEmpty else {
            throw GoogleMapsLinkError.noStops
        }

        let waypointTexts = (query["waypoints"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: true)
            .map { decode(String($0)) }
            .filter { !$0.isEmpty }

        guard waypointTexts.count <= maximumWaypoints else {
            throw GoogleMapsLinkError.tooManyWaypoints(waypointTexts.count)
        }

        let origin = stop(from: decode(originText))
        let destination = stop(from: decode(destinationText))
        guard !isSameEndpoint(origin, destination) else {
            throw GoogleMapsLinkError.sameEndpoints
        }

        return GoogleMapsRouteLink(
            origin: origin,
            waypoints: waypointTexts.map(stop(from:)),
            destination: destination
        )
    }

    private static func parsePathRoute(_ url: URL) throws -> GoogleMapsRouteLink {
        let path = url.path
        guard let range = path.range(of: "/maps/dir") else {
            throw GoogleMapsLinkError.noStops
        }

        var remainder = String(path[range.upperBound...])
        if remainder.hasPrefix("/") {
            remainder.removeFirst()
        }

        var parts = remainder
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)

        while parts.last?.isEmpty == true {
            parts.removeLast()
        }
        guard !parts.isEmpty else {
            throw GoogleMapsLinkError.noStops
        }

        var stopTexts: [String] = []
        for part in parts {
            let decoded = decode(part)
            if isMetadata(decoded) {
                break
            }
            stopTexts.append(decoded)
        }

        guard let first = stopTexts.first, !first.isEmpty else {
            throw GoogleMapsLinkError.missingOrigin
        }
        guard stopTexts.count >= 2 else {
            throw GoogleMapsLinkError.missingOrigin
        }
        guard let last = stopTexts.last, !last.isEmpty else {
            throw GoogleMapsLinkError.noStops
        }

        let waypointTexts = Array(stopTexts.dropFirst().dropLast())
        guard waypointTexts.count <= maximumWaypoints else {
            throw GoogleMapsLinkError.tooManyWaypoints(waypointTexts.count)
        }

        let origin = stop(from: first)
        let destination = stop(from: last)
        guard !isSameEndpoint(origin, destination) else {
            throw GoogleMapsLinkError.sameEndpoints
        }

        return GoogleMapsRouteLink(
            origin: origin,
            waypoints: waypointTexts.map(stop(from:)),
            destination: destination
        )
    }

    private static func stop(from text: String) -> GoogleMapsStop {
        GoogleMapsStop(text: text, coordinate: coordinate(from: text))
    }

    private static func decode(_ value: String) -> String {
        let percentDecoded = value.removingPercentEncoding ?? value
        return percentDecoded
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMetadata(_ value: String) -> Bool {
        value.hasPrefix("@")
            || value.hasPrefix("data=")
            || value.hasPrefix("!")
            || value.hasPrefix("am=")
            || value.hasPrefix("entry=")
            || value.hasPrefix("shorturl=")
    }

    private static func isSameEndpoint(
        _ origin: GoogleMapsStop,
        _ destination: GoogleMapsStop
    ) -> Bool {
        if let first = origin.coordinate, let second = destination.coordinate {
            return first.distance(to: second) <= 25
        }
        return origin.text.compare(
            destination.text,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }

    private static func validateTravelMode(
        travelMode: String?,
        directionFlag: String?
    ) throws {
        if let travelMode, !travelMode.isEmpty {
            let mode = travelMode.lowercased()
            guard mode == "driving" || mode == "d" else {
                throw GoogleMapsLinkError.unsupportedTravelMode(mode)
            }
        }

        guard let directionFlag, !directionFlag.isEmpty else { return }
        switch directionFlag.lowercased() {
        case "d", "driving", "0":
            return
        case "w", "walking":
            throw GoogleMapsLinkError.unsupportedTravelMode("walking")
        case "b", "bicycling", "cycling":
            throw GoogleMapsLinkError.unsupportedTravelMode("cycling")
        case "r", "transit":
            throw GoogleMapsLinkError.unsupportedTravelMode("transit")
        default:
            return
        }
    }
}
