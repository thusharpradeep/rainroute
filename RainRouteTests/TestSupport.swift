import Foundation
@testable import RainRoute

enum TestSupport {
    static let baseDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 24
        components.hour = 0
        components.minute = 0
        return calendar.date(from: components)!
    }()

    static func date(hour: Int, minute: Int = 0) -> Date {
        baseDate.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    static func hourlyForecast(
        startHour: Int,
        values: [(Double, Double?)]
    ) -> HourlyForecast {
        let hours = values.enumerated().map { index, value in
            HourlyForecast.Hour(
                time: date(hour: startHour + index),
                precipitationMM: value.0,
                probability: value.1
            )
        }
        return HourlyForecast(hours: hours)
    }

    static func simpleRoute(
        totalMeters: Double = 30_000,
        durationSeconds: TimeInterval = 3_600
    ) -> Route {
        Route.synthetic(
            coordinates: [
                GeoCoordinate(latitude: 10.0, longitude: 75.9),
                GeoCoordinate(latitude: 10.0, longitude: 76.2)
            ],
            totalDistanceMeters: totalMeters,
            totalDurationSeconds: durationSeconds
        )
    }

    /// Fixed Tirur-to-Kochi fixture. Coordinates approximate the real corridor.
    /// No live OSRM or weather call is involved.
    static func tirurKochiRoute() -> Route {
        Route.synthetic(
            coordinates: [
                GeoCoordinate(latitude: 10.9137, longitude: 75.9215),
                GeoCoordinate(latitude: 10.8000, longitude: 76.0000),
                GeoCoordinate(latitude: 10.6500, longitude: 76.0700),
                GeoCoordinate(latitude: 10.5276, longitude: 76.2144),
                GeoCoordinate(latitude: 10.3500, longitude: 76.3000),
                GeoCoordinate(latitude: 10.1960, longitude: 76.3860),
                GeoCoordinate(latitude: 10.1076, longitude: 76.3516),
                GeoCoordinate(latitude: 9.9900, longitude: 76.3000),
                GeoCoordinate(latitude: 9.9312, longitude: 76.2673)
            ],
            totalDistanceMeters: 128_870,
            totalDurationSeconds: 8_678
        )
    }

    static func uniformForecasts(
        route: Route,
        forecast: HourlyForecast,
        segmentCount: Int = RouteSlicer.defaultSegmentCount
    ) throws -> [GridCell: HourlyForecast] {
        let cells = try RouteSlicer.gridCells(route: route, segmentCount: segmentCount)
        return Dictionary(uniqueKeysWithValues: cells.map { ($0, forecast) })
    }

    static func forecasts(
        route: Route,
        segmentCount: Int = RouteSlicer.defaultSegmentCount,
        make: (Int, GridCell) -> HourlyForecast
    ) throws -> [GridCell: HourlyForecast] {
        let cells = try RouteSlicer.gridCells(route: route, segmentCount: segmentCount)
        var result: [GridCell: HourlyForecast] = [:]
        for (index, cell) in cells.enumerated() {
            result[cell] = make(index, cell)
        }
        return result
    }
}
