import SwiftUI

struct LiveRideCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    @State private var isUpdatingRoute = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        model.hasArrived ? "Arrived" : "Live ride",
                        systemImage: model.hasArrived ? "checkmark.circle.fill" : "location.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(model.hasArrived ? Theme.safe : Theme.accent)

                    Spacer()

                    if let updated = model.lastUpdated {
                        Text("Weather \(updated.formatted(.dateTime.hour().minute()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let snapshot = model.liveSnapshot {
                    ProgressView(value: min(max(snapshot.progress.fraction, 0), 1))
                        .tint(Theme.accent)

                    HStack(spacing: 14) {
                        InlineMetric(
                            icon: "checkmark.circle",
                            label: "Done",
                            value: distance(snapshot.progress.distanceMeters)
                        )
                        InlineMetric(
                            icon: "flag.checkered",
                            label: "To go",
                            value: distance(snapshot.result.totalDistanceMeters)
                        )
                        InlineMetric(
                            icon: "clock",
                            label: "ETA",
                            value: snapshot.result.arrival.formatted(.dateTime.hour().minute())
                        )
                    }

                    HStack(spacing: 8) {
                        Label(
                            "GPS ±\(Int(snapshot.accuracyMeters.rounded())) m",
                            systemImage: "location.circle"
                        )
                        Spacer(minLength: 0)
                        Text("\(Int((snapshot.progress.fraction * 100).rounded()))% complete")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if model.isWaitingForGPS {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for a GPS fix…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.hasArrived {
                    Text("You have arrived. End the route when you are ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.isOffRoute, let snapshot = model.liveSnapshot {
                    offRouteWarning(distance: snapshot.progress.offRouteMeters)
                }

                if let error = model.liveErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func offRouteWarning(distance: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "About \(Int(distance.rounded())) m off the planned route",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.caution)

            Text("RainRoute does not reroute automatically. Keep going, or update the route from your current position.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard !isUpdatingRoute else { return }
                isUpdatingRoute = true
                Task { @MainActor in
                    await model.recalculateFromHere(settings: settings)
                    isUpdatingRoute = false
                }
            } label: {
                HStack(spacing: 7) {
                    if isUpdatingRoute {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isUpdatingRoute ? "Updating route…" : "Update route from here")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(
                    Theme.caution,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingRoute)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.caution.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.caution.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func distance(_ meters: Double) -> String {
        let kilometres = meters / 1_000
        if kilometres < 1 {
            return "\(Int(meters.rounded())) m"
        }
        return "\(kilometres.formatted(.number.precision(.fractionLength(1)))) km"
    }
}
