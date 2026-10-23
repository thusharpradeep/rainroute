import Foundation
import XCTest
@testable import RainRoute

private final class MutableClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor FakeWeatherService: WeatherForecastProviding {
    private var requests: [[GridCell]] = []
    private let forecast: HourlyForecast

    init(forecast: HourlyForecast) {
        self.forecast = forecast
    }

    func forecasts(
        for cells: [GridCell],
        now: Date
    ) async throws -> [GridCell: HourlyForecast] {
        requests.append(cells)
        return Dictionary(uniqueKeysWithValues: cells.map { ($0, forecast) })
    }

    func recordedRequests() -> [[GridCell]] {
        requests
    }
}

final class WeatherCacheTests: XCTestCase {
    private var sampleForecast: HourlyForecast {
        TestSupport.hourlyForecast(startHour: 11, values: [(0.4, 0.6)])
    }

    private var sampleCell: GridCell {
        GridCell(latitudeTenths: 109, longitudeTenths: 759)
    }

    func testCacheStoresAndRetrievesAForecast() async {
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(ttl: 1_800, now: { clock.now })
        await cache.store(sampleForecast, for: sampleCell, at: clock.now)

        let hit = await cache.forecast(for: sampleCell)
        XCTAssertEqual(hit, sampleForecast)
    }

    func testCacheExpiresAtTheTTLBoundary() async {
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(ttl: 1_800, now: { clock.now })
        await cache.store(sampleForecast, for: sampleCell, at: clock.now)

        clock.now = clock.now.addingTimeInterval(1_799)
        let stillValid = await cache.forecast(for: sampleCell)
        XCTAssertNotNil(stillValid)

        clock.now = clock.now.addingTimeInterval(1)
        let expired = await cache.forecast(for: sampleCell)
        XCTAssertNil(expired)
        let count = await cache.count()
        XCTAssertEqual(count, 0)
    }

    func testRemoveAllClearsTheCache() async {
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(ttl: 1_800, now: { clock.now })
        await cache.store(sampleForecast, for: sampleCell, at: clock.now)
        await cache.removeAll()
        let hit = await cache.forecast(for: sampleCell)
        XCTAssertNil(hit)
    }

    func testRepositoryReusesCachedCells() async throws {
        let service = FakeWeatherService(forecast: sampleForecast)
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(now: { clock.now })
        let repository = WeatherRepository(service: service, cache: cache, chunkSize: 20)
        let cells = [
            sampleCell,
            GridCell(latitudeTenths: 99, longitudeTenths: 763)
        ]

        _ = try await repository.forecasts(for: cells, now: clock.now)
        _ = try await repository.forecasts(for: cells, now: clock.now)

        let requests = await service.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testForceRefreshBypassesTheCache() async throws {
        let service = FakeWeatherService(forecast: sampleForecast)
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(now: { clock.now })
        let repository = WeatherRepository(service: service, cache: cache, chunkSize: 20)
        let cells = [sampleCell]

        _ = try await repository.forecasts(for: cells, now: clock.now)
        _ = try await repository.forecasts(for: cells, now: clock.now, forceRefresh: true)

        let requests = await service.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testRepositoryChunksLargeCellSets() async throws {
        let service = FakeWeatherService(forecast: sampleForecast)
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(now: { clock.now })
        let repository = WeatherRepository(service: service, cache: cache, chunkSize: 20)
        let cells = (0..<45).map {
            GridCell(latitudeTenths: $0, longitudeTenths: 0)
        }

        _ = try await repository.forecasts(for: cells, now: clock.now)

        let requests = await service.recordedRequests()
        XCTAssertEqual(requests.map(\.count), [20, 20, 5])
    }

    func testInvalidateCacheForcesAFetch() async throws {
        let service = FakeWeatherService(forecast: sampleForecast)
        let clock = MutableClock(TestSupport.baseDate)
        let cache = WeatherCache(now: { clock.now })
        let repository = WeatherRepository(service: service, cache: cache, chunkSize: 20)
        let cells = [sampleCell]

        _ = try await repository.forecasts(for: cells, now: clock.now)
        await repository.invalidateCache()
        _ = try await repository.forecasts(for: cells, now: clock.now)

        let requests = await service.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }
}
