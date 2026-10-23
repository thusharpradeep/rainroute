import Foundation

/// Hourly forecast values. Open-Meteo's hourly precipitation is the sum over the
/// **preceding** hour: the value labelled 15:00 covers 14:00–15:00. An ETA is
/// therefore matched to the first hourly label at or after that instant.
struct HourlyForecast: Equatable, Sendable {
    struct Hour: Equatable, Sendable {
        /// The label at the end of the hour the value describes.
        let time: Date
        let precipitationMM: Double
        /// Probability of precipitation, normalised to 0...1. Nil when unavailable.
        let probability: Double?

        init(time: Date, precipitationMM: Double, probability: Double? = nil) {
            self.time = time
            self.precipitationMM = precipitationMM
            self.probability = probability.map { min(max($0, 0), 1) }
        }
    }

    let hours: [Hour]

    init(hours: [Hour]) {
        self.hours = hours.sorted { $0.time < $1.time }
    }

    /// Returns the bucket whose preceding hour contains `date`.
    ///
    /// - 14:37 -> 15:00 bucket
    /// - 15:00 -> 15:00 bucket
    /// - 15:01 -> 16:00 bucket
    func hour(containing date: Date) -> Hour? {
        guard let first = hours.first, let last = hours.last else { return nil }
        guard date >= first.time.addingTimeInterval(-3600), date <= last.time else {
            return nil
        }

        var low = 0
        var high = hours.count
        while low < high {
            let middle = (low + high) / 2
            if hours[middle].time < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < hours.count ? hours[low] : nil
    }
}
