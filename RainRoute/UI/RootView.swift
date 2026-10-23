import MapKit
import SwiftUI

struct RootView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var model = AppModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    JourneySearchCard(model: model, settings: settings)

                    if let errorMessage = model.errorMessage {
                        errorCard(errorMessage)
                    }

                    content
                    AttributionFooter()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsSheet(settings: settings)
            }
            .onChange(of: settings.paceFactor) { _, _ in
                model.recompute(settings: settings)
            }
            .onChange(of: settings.wetThreshold) { _, _ in
                model.recompute(settings: settings)
            }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("RainRoute")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
                if let updated = model.lastUpdated {
                    Text("Updated \(updated.formatted(.dateTime.hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("How much of this ride will be wet? Check any start and destination against the hourly forecast at your ETA.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let route = model.route, let result = model.result {
            RouteMapCard(
                route: route,
                result: result,
                cameraPosition: $cameraPosition
            )
            .id(model.mapRevision)

            WetnessSummaryCard(result: result)

            DepartureSliderCard(model: model, settings: settings)

            if let plan = model.plan {
                BestDepartureCard(plan: plan) {
                    model.useBestDeparture(settings: settings)
                }
            }
        } else if model.isLoading {
            loadingCard
        } else {
            emptyStateCard
        }
    }

    private var loadingCard: some View {
        CardContainer {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Checking the ride")
                        .font(.headline)
                    Text(model.statusMessage ?? "Finding the route and hourly forecast…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var emptyStateCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Label("Wet risk, not certainty", systemImage: "umbrella")
                    .font(.headline)

                Text("RainRoute splits your driving route into roughly 10 km segments, works out when you should reach each one, and reads the hourly forecast for that place and time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    FeatureRow(
                        icon: "magnifyingglass",
                        text: "Type any town, landmark, or address as the start and destination."
                    )
                    FeatureRow(
                        icon: "clock.arrow.circlepath",
                        text: "Move the departure slider to compare leaving now with waiting up to four hours."
                    )
                    FeatureRow(
                        icon: "speedometer",
                        text: "Set your real riding pace in Settings so the ETAs match how you ride."
                    )
                }

                Divider()

                Text("Forecasts are hourly and about 9 km wide. A dry result does not guarantee a dry ride, and a wet result does not promise rain on every kilometre.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .font(.subheadline)
                .padding(.top, 1)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                model.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.caution.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.caution.opacity(0.35), lineWidth: 0.5)
        )
    }
}
