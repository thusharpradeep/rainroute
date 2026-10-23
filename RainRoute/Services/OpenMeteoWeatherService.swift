import Foundation

protocol WeatherForecastProviding: Sendable {
    func forecasts(
        for cells: [GridCell],
        now: Date
    ) async throws -> [GridCell: HourlyForecast]
}

struct OpenMeteoWeatherService: WeatherForecastProviding, Sendable {
    var baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    var session: URLSession = .shared

    func forecasts(
        for cells: [GridCell],
        now: Date
    ) async throws -> [GridCell: HourlyForecast] {
        guard !cells.isEmpty else { return [:] }

        let latitudes = cells
            .map { String($0.coordinate.latitude) }
            .joined(separator: ",")
        let longitudes = cells
            .map { String($0.coordinate.longitude) }
            .joined(separator: ",")

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: latitudes),
            URLQueryItem(name: "longitude", value: longitudes),
            URLQueryItem(name: "hourly", value: "precipitation,precipitation_probability"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "GMT"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        let data = try await HTTP.data(
            for: HTTP.request(url: url),
            session: session
        )
        return try Self.decodeForecasts(from: data, cells: cells)
    }

    static func decodeForecasts(
        from data: Data,
        cells: [GridCell]
    ) throws -> [GridCell: HourlyForecast] {
        let decoder = JSONDecoder()
        let responses: [OpenMeteoResponse]

        if let list = try? decoder.decode([OpenMeteoResponse].self, from: data) {
            responses = list
        } else {
            do {
                responses = [try decoder.decode(OpenMeteoResponse.self, from: data)]
            } catch {
                throw APIError.decoding("weather response")
            }
        }

        guard responses.count == cells.count else {
            throw APIError.incompleteForecast
        }

        var result: [GridCell: HourlyForecast] = [:]
        for (cell, response) in zip(cells, responses) {
            if let reason = response.reason, response.error == true {
                throw APIError.service(reason)
            }
            guard let hourly = response.hourly else {
                throw APIError.decoding("weather response")
            }
            guard let times = hourly.time,
                  let precipitation = hourly.precipitation else {
                throw APIError.decoding("weather response")
            }

            let count = min(times.count, precipitation.count)
            var hours: [HourlyForecast.Hour] = []
            hours.reserveCapacity(count)

            for index in 0..<count {
                guard let value = precipitation[index], value.isFinite else {
                    continue
                }
                let probability: Double?
                if let probabilities = hourly.precipitationProbability,
                   index < probabilities.count,
                   let percent = probabilities[index] {
                    probability = min(max(percent / 100, 0), 1)
                } else {
                    probability = nil
                }
                hours.append(
                    HourlyForecast.Hour(
                        time: Date(timeIntervalSince1970: TimeInterval(times[index])),
                        precipitationMM: max(0, value),
                        probability: probability
                    )
                )
            }

            guard !hours.isEmpty else {
                throw APIError.decoding("weather response")
            }
            result[cell] = HourlyForecast(hours: hours)
        }

        return result
    }
}

struct OpenMeteoResponse: Decodable {
    let error: Bool?
    let reason: String?
    let hourly: Hourly?

    struct Hourly: Decodable {
        let time: [Int]?
        let precipitation: [Double?]?
        let precipitationProbability: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case precipitation
            case precipitationProbability = "precipitation_probability"
        }
    }
}
