import Foundation
import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ride pace")
                            Spacer()
                            Text("\(settings.paceFactor, specifier: "%.2f")×")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings.paceFactor },
                                set: { settings.setPaceFactor($0) }
                            ),
                            in: AppSettings.paceRange,
                            step: 0.05
                        )
                        .tint(Theme.accent)
                        HStack {
                            Text("Slower")
                            Spacer()
                            Text("Faster")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Pace")
                } footer: {
                    Text("1.00× uses the map's estimated riding time. 1.20× means you expect to take 20% longer than the map estimate. Calibrate this after a real ride.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Wet threshold")
                            Spacer()
                            Text("\(settings.wetThreshold, specifier: "%.1f") mm/h")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings.wetThreshold },
                                set: { settings.setWetThreshold($0) }
                            ),
                            in: AppSettings.thresholdRange,
                            step: 0.1
                        )
                        .tint(Theme.accent)
                        HStack {
                            Text("0.1")
                            Spacer()
                            Text("2.0")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Wetness")
                } footer: {
                    Text("A segment counts as wet when the forecast precipitation at its ETA is at or above this rate. The default 0.2 mm/h treats barely measurable rain as wet.")
                }

                Section {
                    Link(destination: URL(string: "https://open-meteo.com/")!) {
                        HStack {
                            Label("Open-Meteo", systemImage: "cloud.sun")
                            Spacer()
                            Text("Weather data")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://www.openstreetmap.org/copyright")!) {
                        HStack {
                            Label("OpenStreetMap contributors", systemImage: "map")
                            Spacer()
                            Text("Map data")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://photon.komoot.io/")!) {
                        HStack {
                            Label("Photon", systemImage: "magnifyingglass")
                            Spacer()
                            Text("Place search")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://project-osrm.org/")!) {
                        HStack {
                            Label("OSRM", systemImage: "arrow.triangle.swap")
                            Spacer()
                            Text("Routing")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Data sources")
                } footer: {
                    Text("Weather data by Open-Meteo.com. Maps and routing data © OpenStreetMap contributors. RainRoute does not use paid APIs or send your trips to its own server.")
                }

                Section("About") {
                    HStack {
                        Text("RainRoute")
                        Spacer()
                        Text(version)
                            .foregroundStyle(.secondary)
                    }
                    Text("RainRoute is a planning aid, not a safety device. Forecasts are hourly and roughly 9 km wide, so local rain can differ. Wet risk is not a promise of rain or dryness.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var version: String {
        let short = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
        return "\(short) (\(build))"
    }
}
