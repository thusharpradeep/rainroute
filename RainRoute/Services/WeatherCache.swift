import Foundation

actor WeatherCache {
    private struct Entry {
        let forecast: HourlyForecast
        let fetchedAt: Date
    }

    private var entries: [GridCell: Entry] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    init(
        ttl: TimeInterval = 30 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.ttl = ttl
        self.now = now
    }

    func forecast(for cell: GridCell) -> HourlyForecast? {
        guard let entry = entries[cell] else { return nil }
        if now().timeIntervalSince(entry.fetchedAt) >= ttl {
            entries[cell] = nil
            return nil
        }
        return entry.forecast
    }

    func store(
        _ forecast: HourlyForecast,
        for cell: GridCell,
        at date: Date? = nil
    ) {
        entries[cell] = Entry(
            forecast: forecast,
            fetchedAt: date ?? now()
        )
    }

    func removeAll() {
        entries.removeAll()
    }

    func count() -> Int {
        entries.count
    }
}
