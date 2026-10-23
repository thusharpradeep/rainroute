import Foundation

struct OSRMRouter: Sendable {
    var baseURL: URL = URL(string: "https://router.project-osrm.org")!
    var session: URLSession = .shared

    func route(from start: GeoCoordinate, to end: GeoCoordinate) async throws -> Route {
        do {
            return try await fetchRoute(from: start, to: end, annotations: true)
        } catch let error as APIError {
            if case .http(let status, _) = error, status == 400 {
                // The public server may reject annotations; the route is still usable
                // with a constant-speed timing profile.
                return try await fetchRoute(from: start, to: end, annotations: false)
            }
            throw error
        }
    }

    private func fetchRoute(
        from start: GeoCoordinate,
        to end: GeoCoordinate,
        annotations: Bool
    ) async throws -> Route {
        let startCoordinate = "\(start.longitude),\(start.latitude)"
        let endCoordinate = "\(end.longitude),\(end.latitude)"
        var urlString = baseURL.absoluteString
            + "/route/v1/driving/\(startCoordinate);\(endCoordinate)"
            + "?overview=full&geometries=geojson&steps=true&alternatives=false"
        if annotations {
            urlString += "&annotations=duration,distance"
        }
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let data = try await HTTP.data(
            for: HTTP.request(url: url),
            session: session
        )
        return try Self.decodeRoute(from: data)
    }

    static func decodeRoute(from data: Data) throws -> Route {
        let response: OSRMResponse
        do {
            response = try JSONDecoder().decode(OSRMResponse.self, from: data)
        } catch {
            throw APIError.decoding("routing response")
        }

        guard response.code == "Ok" else {
            throw APIError.service(
                response.message ?? "The routing service could not find a route."
            )
        }
        guard let route = response.routes?.first else {
            throw APIError.service("No driving route was found between those places.")
        }
        guard route.distance.isFinite, route.distance > 0,
              route.duration.isFinite, route.duration > 0 else {
            throw APIError.service("The routing service returned an invalid route.")
        }

        let coordinates = route.geometry.coordinates.compactMap { pair -> GeoCoordinate? in
            guard pair.count >= 2,
                  pair[0].isFinite,
                  pair[1].isFinite,
                  (-180...180).contains(pair[0]),
                  (-90...90).contains(pair[1]) else {
                return nil
            }
            return GeoCoordinate(latitude: pair[1], longitude: pair[0])
        }
        guard coordinates.count >= 2 else {
            throw APIError.decoding("route geometry")
        }

        if let profile = annotationProfile(
            route: route,
            coordinates: coordinates
        ) {
            return profile
        }

        return Route.synthetic(
            coordinates: coordinates,
            totalDistanceMeters: route.distance,
            totalDurationSeconds: route.duration
        )
    }

    private static func annotationProfile(
        route: OSRMRoute,
        coordinates: [GeoCoordinate]
    ) -> Route? {
        guard route.legs?.count == 1,
              let annotation = route.legs?.first?.annotation,
              let distances = annotation.distance,
              let durations = annotation.duration,
              distances.count == coordinates.count - 1,
              durations.count == coordinates.count - 1 else {
            return nil
        }

        var cumulativeDistances = [0.0]
        var cumulativeDurations = [0.0]
        cumulativeDistances.reserveCapacity(coordinates.count)
        cumulativeDurations.reserveCapacity(coordinates.count)

        for index in distances.indices {
            let distance = distances[index]
            let duration = durations[index]
            guard distance.isFinite, duration.isFinite,
                  distance >= 0, duration >= 0 else {
                return nil
            }
            cumulativeDistances.append(cumulativeDistances[index] + distance)
            cumulativeDurations.append(cumulativeDurations[index] + duration)
        }

        guard let distanceTotal = cumulativeDistances.last,
              let durationTotal = cumulativeDurations.last,
              distanceTotal > 0,
              durationTotal > 0 else {
            return nil
        }

        let distanceTolerance = max(5.0, route.distance * 0.05)
        let durationTolerance = max(5.0, route.duration * 0.05)
        guard abs(distanceTotal - route.distance) <= distanceTolerance,
              abs(durationTotal - route.duration) <= durationTolerance else {
            return nil
        }

        // Normalise to OSRM's totals so the displayed arrival time and the
        // per-segment ETAs stay consistent with the route summary.
        let distanceScale = route.distance / distanceTotal
        let durationScale = route.duration / durationTotal
        let normalizedDistances = cumulativeDistances.map { $0 * distanceScale }
        let normalizedDurations = cumulativeDurations.map { $0 * durationScale }

        return Route(
            coordinates: coordinates,
            cumulativeDistances: normalizedDistances,
            cumulativeDurations: normalizedDurations
        )
    }
}

struct OSRMResponse: Decodable {
    let code: String
    let message: String?
    let routes: [OSRMRoute]?
}

struct OSRMRoute: Decodable {
    let distance: Double
    let duration: Double
    let geometry: Geometry
    let legs: [Leg]?

    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }

    struct Leg: Decodable {
        let annotation: Annotation?
        let steps: [Step]?
    }

    struct Annotation: Decodable {
        let distance: [Double]?
        let duration: [Double]?
    }

    struct Step: Decodable {
        let distance: Double
        let duration: Double
        let geometry: OSRMRoute.Geometry?
    }
}
