import SwiftUI
import UIKit

struct RouteActionsCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    @Environment(\.openURL) private var openURL
    @State private var isConfirmingEnd = false

    var body: some View {
        CardContainer {
            VStack(spacing: 11) {
                HStack(spacing: 10) {
                    actionButton(
                        title: "Open in Google Maps",
                        icon: "arrow.triangle.turn.up.right.diamond.fill",
                        action: openGoogleMaps
                    )
                    actionButton(
                        title: "Open in Apple Maps",
                        icon: "map.fill",
                        action: openAppleMaps
                    )
                }

                Button {
                    if model.isRiding {
                        isConfirmingEnd = true
                    } else {
                        model.startRide(settings: settings)
                    }
                } label: {
                    Label(
                        model.isRiding ? "End route" : "Start ride",
                        systemImage: model.isRiding ? "stop.circle.fill" : "location.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(
                        model.isRiding ? Theme.danger : Theme.safe,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    model.isRiding
                        ? "Stops GPS tracking for this ride."
                        : "Starts GPS tracking and keeps the screen awake."
                )

                if model.isRiding && model.isWaitingForGPS {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for a GPS fix…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if !model.isRiding {
                    Text("Live ride uses your location while the app is open and keeps the screen awake.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog(
            "End this ride?",
            isPresented: $isConfirmingEnd,
            titleVisibility: .visible
        ) {
            Button("End route", role: .destructive) {
                model.endRide()
            }
            Button("Keep riding", role: .cancel) {}
        } message: {
            Text("Your planned route and forecast stay on screen.")
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .foregroundStyle(Theme.accent)
            .background(
                Theme.background.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.mapStartCoordinate == nil || model.mapDestinationCoordinate == nil)
    }

    private func openGoogleMaps() {
        guard let start = model.mapStartCoordinate,
              let destination = model.mapDestinationCoordinate else {
            return
        }
        let waypoints = model.mapWaypoints.map(\.coordinate)

        if let appURL = RouteLinks.googleMapsApp(
            start: start,
            destination: destination,
            waypoints: waypoints
        ), UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }

        openURL(
            RouteLinks.googleMaps(
                start: start,
                destination: destination,
                waypoints: waypoints
            )
        )
    }

    private func openAppleMaps() {
        guard let start = model.mapStartCoordinate,
              let destination = model.mapDestinationCoordinate else {
            return
        }
        openURL(RouteLinks.appleMaps(start: start, destination: destination))
    }
}
