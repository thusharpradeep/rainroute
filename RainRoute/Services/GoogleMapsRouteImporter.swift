import Foundation

struct ImportedRoute: Equatable, Sendable {
    let origin: Place
    let waypoints: [Place]
    let destination: Place

    var stops: [Place] {
        [origin] + waypoints + [destination]
    }
}

/// Turns a pasted Google Maps directions link into routing anchors.
///
/// Google's share links name the start, destination, and stops but do not carry
/// the road geometry. Place names are resolved through Photon; coordinate pairs
/// are used directly. OSRM then routes through the anchors in order.
struct GoogleMapsRouteImporter {
    var resolver: any GoogleMapsLinkResolving
    var geocoder: any PlaceSearching

    init(
        resolver: any GoogleMapsLinkResolving = GoogleMapsLinkResolver(),
        geocoder: any PlaceSearching = PhotonGeocoder()
    ) {
        self.resolver = resolver
        self.geocoder = geocoder
    }

    func importRoute(from rawLink: String) async throws -> ImportedRoute {
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GoogleMapsLinkError.invalidLink
        }

        let withoutNewlines = trimmed
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let encoded = withoutNewlines.replacingOccurrences(of: " ", with: "%20")
        let normalized = encoded.contains("://") ? encoded : "https://\(encoded)"
        guard let url = URL(string: normalized), url.host != nil else {
            throw GoogleMapsLinkError.invalidLink
        }

        let resolved = try await resolver.resolve(url)
        let link = try GoogleMapsLinkParser.parse(resolved)

        let origin = try await place(for: link.origin)
        var waypoints: [Place] = []
        waypoints.reserveCapacity(link.waypoints.count)
        for stop in link.waypoints {
            waypoints.append(try await place(for: stop))
        }
        let destination = try await place(for: link.destination)

        var deduped: [Place] = []
        for anchor in [origin] + waypoints + [destination] {
            if let last = deduped.last,
               last.coordinate.distance(to: anchor.coordinate) <= 25 {
                continue
            }
            deduped.append(anchor)
        }

        guard let first = deduped.first,
              let last = deduped.last,
              deduped.count >= 2,
              first.coordinate.distance(to: last.coordinate) > 25 else {
            throw GoogleMapsLinkError.sameEndpoints
        }

        return ImportedRoute(
            origin: first,
            waypoints: Array(deduped.dropFirst().dropLast()),
            destination: last
        )
    }

    private func place(for stop: GoogleMapsStop) async throws -> Place {
        if let coordinate = stop.coordinate {
            return Place(
                id: "google-maps:\(coordinate.latitude),\(coordinate.longitude)",
                name: stop.text,
                subtitle: "Imported pin",
                coordinate: coordinate
            )
        }

        let query = stop.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw GoogleMapsLinkError.placeNotFound(stop.text)
        }

        let results = try await geocoder.search(query)
        guard let first = results.first else {
            throw GoogleMapsLinkError.placeNotFound(query)
        }
        return first
    }
}
