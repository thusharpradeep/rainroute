import Foundation

/// A latitude/longitude pair used by the core model. Deliberately independent of
/// CoreLocation so the logic can be tested without a simulator location stack.
struct GeoCoordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres.
    func distance(to other: GeoCoordinate) -> Double {
        let earthRadius = 6_371_000.0
        let latitude1 = latitude * .pi / 180
        let latitude2 = other.latitude * .pi / 180
        let deltaLatitude = (other.latitude - latitude) * .pi / 180
        let deltaLongitude = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(latitude1) * cos(latitude2)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }
}

/// A weather cache cell. Open-Meteo's model grid is roughly 9 km, so snapping to
/// 0.1 degrees avoids duplicate requests for neighbouring route samples.
struct GridCell: Hashable, Codable, Sendable, Identifiable {
    let latitudeTenths: Int
    let longitudeTenths: Int

    init(coordinate: GeoCoordinate) {
        latitudeTenths = Int((coordinate.latitude * 10).rounded())
        longitudeTenths = Int((coordinate.longitude * 10).rounded())
    }

    init(latitudeTenths: Int, longitudeTenths: Int) {
        self.latitudeTenths = latitudeTenths
        self.longitudeTenths = longitudeTenths
    }

    var id: String {
        "\(latitudeTenths),\(longitudeTenths)"
    }

    var coordinate: GeoCoordinate {
        GeoCoordinate(
            latitude: Double(latitudeTenths) / 10,
            longitude: Double(longitudeTenths) / 10
        )
    }
}
