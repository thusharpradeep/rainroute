import Foundation
import MapKit
import SwiftUI

struct RouteMapCard: View {
    let route: Route
    let result: WetnessResult
    @Binding var cameraPosition: MapCameraPosition
    var liveSnapshot: LiveRideSnapshot?
    var routeSource: RouteSource = .typed
    var isRiding = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        isRiding ? "Rain on the remaining route" : "Rain along the route",
                        systemImage: "map"
                    )
                    .font(.headline)
                    Spacer()
                    Text("\(Int(result.roundedWetPercent))% wet")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.riskColor(for: result.roundedWetPercent))
                }

                Map(position: $cameraPosition) {
                    MapPolyline(coordinates: route.coordinates.map(\.mapCoordinate))
                        .stroke(
                            isRiding ? Color.gray.opacity(0.38) : Color.white.opacity(0.92),
                            lineWidth: isRiding ? 7 : 10
                        )

                    ForEach(result.segments) { assessment in
                        MapPolyline(
                            coordinates: assessment.segment.polyline.map(\.mapCoordinate)
                        )
                        .stroke(assessment.intensity.color, lineWidth: 6)
                    }

                    if !isRiding, let start = route.coordinates.first {
                        Annotation("Start", coordinate: start.mapCoordinate) {
                            mapMarker(color: Theme.accent)
                        }
                    }

                    if let destination = route.coordinates.last {
                        Annotation("Destination", coordinate: destination.mapCoordinate) {
                            mapMarker(color: Theme.heavyRain)
                        }
                    }

                    if let liveSnapshot {
                        Annotation("You", coordinate: liveSnapshot.location.mapCoordinate) {
                            currentLocationMarker
                        }
                    }
                }
                .mapStyle(.standard)
                .frame(height: 285)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    routePill
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    legend
                        .padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let liveSnapshot {
                        recenterButton(to: liveSnapshot.location)
                            .padding(10)
                    }
                }
                .onAppear {
                    cameraPosition = .region(route.boundingRegion)
                }

                Text(
                    isRiding
                        ? "The grey line is your planned route. Colours show the forecast for the segments still ahead."
                        : "Colours show the hourly rain rate forecast at each segment's ETA. Grey means below your wet threshold."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var routePill: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isRiding ? "\(distanceText) left" : distanceText)
                .font(.caption.weight(.semibold))
            Text(isRiding ? "\(durationText) left" : durationText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if routeSource == .googleMaps {
                Text(isRiding ? "Imported, live" : "Imported route")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(RainIntensity.allCases, id: \.self) { intensity in
                HStack(spacing: 4) {
                    Circle()
                        .fill(intensity.color)
                        .frame(width: 6, height: 6)
                    Text(intensity.label)
                        .font(.caption2)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    private func mapMarker(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
        }
    }

    private var currentLocationMarker: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 1)
            Circle()
                .fill(Color.blue)
                .frame(width: 18, height: 18)
        }
        .accessibilityLabel("Your current location")
    }

    private func recenterButton(to coordinate: GeoCoordinate) -> some View {
        Button {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate.mapCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
        } label: {
            Image(systemName: "location.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recentre on my location")
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

extension GeoCoordinate {
    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Route {
    var boundingRegion: MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? 0
        let maximumLatitude = latitudes.max() ?? 0
        let minimumLongitude = longitudes.min() ?? 0
        let maximumLongitude = longitudes.max() ?? 0

        let latitudeDelta = max((maximumLatitude - minimumLatitude) * 1.35, 0.02)
        let longitudeDelta = max((maximumLongitude - minimumLongitude) * 1.35, 0.02)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}
