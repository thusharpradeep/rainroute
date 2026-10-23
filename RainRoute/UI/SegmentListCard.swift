import SwiftUI

struct SegmentListCard: View {
    let result: WetnessResult
    var isLive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasWetSegment: Bool {
        result.segments.contains(where: \.isWet)
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        isLive ? "Segments ahead" : "Segments",
                        systemImage: "list.number"
                    )
                    .font(.headline)
                    Spacer()
                    Text("\(result.totalSegments)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(
                    isLive
                        ? "Only segments still ahead are shown. Numbers keep their original order."
                        : "Every segment in order, with the forecast for its arrival time."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if result.segments.isEmpty {
                    Text("No segments are left on this route.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    TimelineView(
                        .animation(
                            minimumInterval: 1.0 / 12.0,
                            paused: reduceMotion || !hasWetSegment
                        )
                    ) { timeline in
                        LazyVStack(spacing: 0) {
                            ForEach(Array(result.segments.enumerated()), id: \.element.id) { index, assessment in
                                SegmentRow(
                                    assessment: assessment,
                                    time: timeline.date.timeIntervalSinceReferenceDate,
                                    animates: !reduceMotion
                                )

                                if index < result.segments.count - 1 {
                                    Divider()
                                        .opacity(0.6)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SegmentRow: View {
    let assessment: SegmentAssessment
    let time: TimeInterval
    let animates: Bool

    var body: some View {
        HStack(spacing: 12) {
            SegmentWeatherGlyph(
                assessment: assessment,
                time: time,
                animates: animates
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("Segment \(assessment.segment.index + 1)")
                        .font(.subheadline.weight(.semibold))
                    Text(assessment.isWet ? "Wet" : "Dry")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(
                            assessment.isWet ? assessment.intensity.color : Theme.dry
                        )
                        .background(
                            (assessment.isWet ? assessment.intensity.color : Theme.dry)
                                .opacity(0.12),
                            in: Capsule()
                        )
                }

                Text(distanceRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    Label(etaText, systemImage: "clock")
                    Text(rateText)
                    Text(probabilityText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var distanceRange: String {
        let start = assessment.segment.startDistanceMeters / 1_000
        let end = assessment.segment.endDistanceMeters / 1_000
        return "\(kilometres(start))–\(kilometres(end)) km"
    }

    private var etaText: String {
        assessment.segment.eta.formatted(.dateTime.hour().minute())
    }

    private var rateText: String {
        "\(millimetres(assessment.precipitationMM)) mm/h"
    }

    private var probabilityText: String {
        guard let probability = assessment.probability else {
            return "probability unavailable"
        }
        return "\(Int((probability * 100).rounded()))% probability"
    }

    private var accessibilityLabel: String {
        let status = assessment.isWet ? "wet" : "dry"
        let intensity = assessment.isWet
            ? ", \(assessment.intensity.label.lowercased()) rain"
            : ""
        let probability: String
        if let value = assessment.probability {
            probability = "\(Int((value * 100).rounded())) percent probability"
        } else {
            probability = "probability unavailable"
        }
        return "Segment \(assessment.segment.index + 1), \(distanceRange), \(status)\(intensity), \(rateText), \(probability), arriving \(etaText)."
    }

    private func kilometres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func millimetres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct SegmentWeatherGlyph: View {
    let assessment: SegmentAssessment
    let time: TimeInterval
    let animates: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    (assessment.isWet ? assessment.intensity.color : Theme.dry)
                        .opacity(0.13)
                )

            if assessment.isWet {
                ZStack {
                    Image(systemName: "cloud.rain.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(assessment.intensity.color)
                        .offset(y: -3)

                    if animates {
                        ForEach(0..<3, id: \.self) { drop in
                            Capsule()
                                .fill(assessment.intensity.color)
                                .frame(width: 1.5, height: 3.5)
                                .offset(
                                    x: CGFloat(drop - 1) * 3.8,
                                    y: 3 + CGFloat(phase(drop) * 7)
                                )
                                .opacity(1 - phase(drop))
                        }
                    }
                }
            } else {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.dry)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private func phase(_ drop: Int) -> Double {
        let raw = time * 0.9 + Double(drop) * 0.37
        return raw.truncatingRemainder(dividingBy: 1)
    }
}
