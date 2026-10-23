import Foundation

struct DeparturePlan: Equatable, Sendable {
    let now: WetnessResult
    let best: WetnessResult
    let bestDeparture: Date
    let shouldWait: Bool
    let segmentsSaved: Int
}

enum DeparturePlanner {
    static let searchWindow: TimeInterval = 4 * 60 * 60
    static let step: TimeInterval = 15 * 60

    static func plan(
        route: Route,
        now: Date,
        paceFactor: Double,
        threshold: Double,
        forecasts: [GridCell: HourlyForecast],
        segmentCount: Int = RouteSlicer.defaultSegmentCount,
        window: TimeInterval = DeparturePlanner.searchWindow,
        step: TimeInterval = DeparturePlanner.step
    ) throws -> DeparturePlan {
        guard window >= 0, step > 0 else {
            throw RouteError.invalidRoute
        }

        let nowResult = try WetnessEngine.evaluate(
            route: route,
            departure: now,
            paceFactor: paceFactor,
            threshold: threshold,
            forecasts: forecasts,
            segmentCount: segmentCount
        )

        var candidates: [(departure: Date, result: WetnessResult)] = [
            (now, nowResult)
        ]

        var offset = step
        while offset <= window + 0.001 {
            let departure = now.addingTimeInterval(offset)
            if let result = try? WetnessEngine.evaluate(
                route: route,
                departure: departure,
                paceFactor: paceFactor,
                threshold: threshold,
                forecasts: forecasts,
                segmentCount: segmentCount
            ) {
                candidates.append((departure, result))
            }
            offset += step
        }

        let ordered = candidates.sorted { lhs, rhs in
            if lhs.result.wetSegmentCount != rhs.result.wetSegmentCount {
                return lhs.result.wetSegmentCount < rhs.result.wetSegmentCount
            }
            let leftProbability = lhs.result.probabilityWeightedShare ?? 1
            let rightProbability = rhs.result.probabilityWeightedShare ?? 1
            if abs(leftProbability - rightProbability) > 1e-12 {
                return leftProbability < rightProbability
            }
            return lhs.departure < rhs.departure
        }

        guard let bestCandidate = ordered.first else {
            return DeparturePlan(
                now: nowResult,
                best: nowResult,
                bestDeparture: now,
                shouldWait: false,
                segmentsSaved: 0
            )
        }

        let savesSegments = bestCandidate.result.wetSegmentCount
            < nowResult.wetSegmentCount

        guard savesSegments else {
            return DeparturePlan(
                now: nowResult,
                best: nowResult,
                bestDeparture: now,
                shouldWait: false,
                segmentsSaved: 0
            )
        }

        return DeparturePlan(
            now: nowResult,
            best: bestCandidate.result,
            bestDeparture: bestCandidate.departure,
            shouldWait: true,
            segmentsSaved: nowResult.wetSegmentCount - bestCandidate.result.wetSegmentCount
        )
    }
}
