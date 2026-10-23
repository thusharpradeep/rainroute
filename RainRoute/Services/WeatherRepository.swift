import Foundation

actor WeatherRepository {
    private let service: any WeatherForecastProviding
    private let cache: WeatherCache
    private let chunkSize: Int

    init(
        service: any WeatherForecastProviding = OpenMeteoWeatherService(),
        cache: WeatherCache = WeatherCache(),
        chunkSize: Int = 20
    ) {
        self.service = service
        self.cache = cache
        self.chunkSize = max(1, chunkSize)
    }

    func forecasts(
        for cells: [GridCell],
        now: Date,
        forceRefresh: Bool = false
    ) async throws -> [GridCell: HourlyForecast] {
        let unique = Array(Set(cells)).sorted { $0.id < $1.id }
        guard !unique.isEmpty else { return [:] }

        var result: [GridCell: HourlyForecast] = [:]
        var missing: [GridCell] = []

        for cell in unique {
            if !forceRefresh, let cached = await cache.forecast(for: cell) {
                result[cell] = cached
            } else {
                missing.append(cell)
            }
        }

        var index = 0
        while index < missing.count {
            let end = min(index + chunkSize, missing.count)
            let chunk = Array(missing[index..<end])
            let fetched = try await service.forecasts(for: chunk, now: now)
            for cell in chunk {
                guard let forecast = fetched[cell] else {
                    throw APIError.incompleteForecast
                }
                result[cell] = forecast
                await cache.store(forecast, for: cell, at: now)
            }
            index = end
        }

        guard result.count == unique.count else {
            throw APIError.incompleteForecast
        }
        return result
    }

    func invalidateCache() async {
        await cache.removeAll()
    }
}
