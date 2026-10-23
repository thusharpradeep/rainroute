import Foundation
import SwiftUI

struct WetnessSummaryCard: View {
    let result: WetnessResult
    var isLive = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(result.roundedWetPercent)")
                                .font(.system(size: 58, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.riskColor(for: result.roundedWetPercent))
                            Text("%")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Text(isLive ? "of the remaining ride likely wet" : "of the ride likely wet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Text(Theme.riskLabel(for: result.roundedWetPercent))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Theme.riskColor(for: result.roundedWetPercent).opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(Theme.riskColor(for: result.roundedWetPercent))
                }

                Text(result.wetSegmentSummary)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: 14) {
                    InlineMetric(
                        icon: "ruler",
                        label: isLive ? "To go" : "Route",
                        value: distanceText
                    )
                    InlineMetric(
                        icon: "clock",
                        label: isLive ? "Ride left" : "Ride",
                        value: durationText
                    )
                }

                HStack(spacing: 14) {
                    InlineMetric(
                        icon: "arrow.up.right",
                        label: isLive ? "Now" : "Leave",
                        value: result.departure.formatted(.dateTime.hour().minute())
                    )
                    InlineMetric(
                        icon: "arrow.down.left",
                        label: isLive ? "ETA" : "Arrive",
                        value: result.arrival.formatted(.dateTime.hour().minute())
                    )
                }

                confidenceLine

                Text("Wet risk, not certainty. Forecasts are hourly at roughly 9 km resolution, so local rain can be patchier. A segment counts as wet at \(result.threshold, specifier: "%.1f") mm/h or above.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confidenceLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "chart.bar.xaxis")
                .font(.caption)
            if let probability = result.probabilityWeightedShare {
                Text("Probability-weighted risk: \(probability * 100, specifier: "%.0f")%")
            } else {
                Text("Probability data unavailable")
            }
            Spacer(minLength: 0)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private var distanceText: String {
        let kilometres = result.totalDistanceMeters / 1_000
        return "\(kilometres.formatted(.number.precision(.fractionLength(1)))) km"
    }

    private var durationText: String {
        let minutes = Int((result.totalDurationSeconds / 60).rounded())
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours) h \(remainder) min"
        }
        return "\(minutes) min"
    }
}
