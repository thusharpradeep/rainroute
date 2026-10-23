import Foundation

enum RouteLinks {
    static func googleMaps(
        start: GeoCoordinate,
        destination: GeoCoordinate,
        waypoints: [GeoCoordinate] = []
    ) -> URL {
        var components = URLComponents()
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: coordinateString(start)),
            URLQueryItem(name: "destination", value: coordinateString(destination))
        ]
        if !waypoints.isEmpty {
            items.append(
                URLQueryItem(
                    name: "waypoints",
                    value: waypoints.map(coordinateString).joined(separator: "|")
                )
            )
        }
        items.append(URLQueryItem(name: "travelmode", value: "driving"))
        components.queryItems = items

        guard let query = components.percentEncodedQuery,
              let url = URL(string: "https://www.google.com/maps/dir/?\(query)") else {
            return URL(string: "https://www.google.com/maps/dir/")!
        }
        return url
    }

    /// The installed Google Maps app's documented directions URL.
    static func googleMapsApp(
        start: GeoCoordinate,
        destination: GeoCoordinate,
        waypoints: [GeoCoordinate] = []
    ) -> URL? {
        var components = URLComponents()
        var items = [
            URLQueryItem(name: "saddr", value: coordinateString(start)),
            URLQueryItem(name: "daddr", value: coordinateString(destination))
        ]
        if !waypoints.isEmpty {
            items.append(
                URLQueryItem(
                    name: "waypoints",
                    value: waypoints.map(coordinateString).joined(separator: "|")
                )
            )
        }
        items.append(URLQueryItem(name: "directionsmode", value: "driving"))
        components.queryItems = items

        guard let query = components.percentEncodedQuery else { return nil }
        return URL(string: "comgooglemaps://?\(query)")
    }

    static func appleMaps(
        start: GeoCoordinate,
        destination: GeoCoordinate
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "saddr", value: coordinateString(start)),
            URLQueryItem(name: "daddr", value: coordinateString(destination)),
            URLQueryItem(name: "dirflg", value: "d")
        ]

        return components.url
            ?? URL(string: "https://maps.apple.com/")!
    }

    /// Always uses a dot decimal separator, regardless of the device locale.
    private static func coordinateString(_ coordinate: GeoCoordinate) -> String {
        String(
            format: "%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinate.latitude,
            coordinate.longitude
        )
    }
}
