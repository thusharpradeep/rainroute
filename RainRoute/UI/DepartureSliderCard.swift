import Foundation
import SwiftUI

struct DepartureSliderCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var sliderValue: Binding<Double> {
        Binding(
            get: { model.departureOffsetMinutes },
            set: { model.updateDepartureOffset($0, settings: settings) }
        )
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Departure time", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    if let departure = model.selectedDeparture {
                        Text(departure.formatted(.dateTime.hour().minute()))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }

                Slider(value: sliderValue, in: 0...240, step: 15)
                    .tint(Theme.accent)
                    .accessibilityLabel("Departure time")
                    .accessibilityValue(offsetText)

                HStack {
                    Text("Now")
                    Spacer()
                    Text("+4 h")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text(offsetText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.departureOffsetMinutes > 0 {
                        Button("Reset to now") {
                            model.updateDepartureOffset(0, settings: settings)
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }

                Text("Moving the slider reuses the forecast already fetched for this route.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var offsetText: String {
        let minutes = Int(model.departureOffsetMinutes.rounded())
        if minutes == 0 {
            return "Leaving now"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "Leaving in \(hours) h \(remainder) min"
        }
        return "Leaving in \(minutes) min"
    }
}
