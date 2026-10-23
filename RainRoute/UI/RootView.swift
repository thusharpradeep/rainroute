import Foundation
import MapKit
import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var model = AppModel()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isShowingSettings = false
    @State private var isShowingImport = false
    @State private var isShowingSplash = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        JourneySearchCard(
                            model: model,
                            settings: settings,
                            onImport: { isShowingImport = true }
                        )

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
                    ToolbarItem(placement: .topBarLeading) {
                        if model.hasResult {
                            Button {
                                Task {
                                    await model.refresh(settings: settings)
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.body.weight(.semibold))
                            }
                            .disabled(model.isLoading)
                            .accessibilityLabel(
                                model.isRiding
                                    ? "Refresh live weather"
                                    : "Refresh the forecast"
                            )
                        }
                    }

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
                .sheet(isPresented: $isShowingImport) {
                    GoogleMapsImportSheet(model: model, settings: settings)
                }
                .onChange(of: settings.paceFactor) { _, _ in
                    model.settingsChanged(settings: settings)
                }
                .onChange(of: settings.wetThreshold) { _, _ in
                    model.settingsChanged(settings: settings)
                }
                .onChange(of: settings.segmentCount) { _, _ in
                    Task {
                        await model.segmentCountChanged(settings: settings)
                    }
                }
            }

            if isShowingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .tint(Theme.accent)
        .task {
            await dismissSplash()
        }
        .onChange(of: model.isRiding) { _, isRiding in
            UIApplication.shared.isIdleTimerDisabled = isRiding
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if model.isRiding {
                    UIApplication.shared.isIdleTimerDisabled = true
                    Task {
                        await model.resumeRideUpdates(settings: settings)
                    }
                }
            case .background:
                model.pauseRideUpdates()
                UIApplication.shared.isIdleTimerDisabled = false
            case .inactive:
                break
            @unknown default:
                break
            }
        }
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

            Text("Check the hourly forecast at your ETA, import a Google Maps route, or track a live ride with GPS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        if let route = model.route, let plannedResult = model.result {
            let result = model.liveResult ?? plannedResult

            RouteMapCard(
                route: route,
                result: result,
                cameraPosition: $cameraPosition,
                liveSnapshot: model.liveSnapshot,
                routeSource: model.routeSource,
                isRiding: model.isRiding
            )
            .id(model.mapRevision)

            RouteActionsCard(model: model, settings: settings)

            if model.isRiding {
                LiveRideCard(model: model, settings: settings)
            }

            WetnessSummaryCard(result: result, isLive: model.isRiding)

            SegmentListCard(result: result, isLive: model.isRiding)

            if !model.isRiding {
                DepartureSliderCard(model: model, settings: settings)

                if let plan = model.plan {
                    BestDepartureCard(plan: plan) {
                        model.useBestDeparture(settings: settings)
                    }
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

                Text("RainRoute splits your driving route into equal-distance segments, works out when you should reach each one, and reads the hourly forecast for that place and time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    FeatureRow(
                        icon: "magnifyingglass",
                        text: "Type any town, landmark, or address as the start and destination."
                    )
                    FeatureRow(
                        icon: "square.and.arrow.down",
                        text: "Or paste a Google Maps directions link to import its start, stops, and destination."
                    )
                    FeatureRow(
                        icon: "slider.horizontal.3",
                        text: "Choose 12 segments by default, or up to 60 for finer detail."
                    )
                    FeatureRow(
                        icon: "location.fill",
                        text: "Start a live ride to follow your GPS position and the remaining wet risk."
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

    private func dismissSplash() async {
        guard isShowingSplash else { return }
        let delay: UInt64 = reduceMotion ? 900_000_000 : 1_600_000_000
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.35)) {
            isShowingSplash = false
        }
    }
}
