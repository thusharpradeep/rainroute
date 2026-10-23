import Foundation
import SwiftUI

struct AttributionFooter: View {
    var body: some View {
        VStack(spacing: 5) {
            Link(
                "Weather data by Open-Meteo.com",
                destination: URL(string: "https://open-meteo.com/")!
            )

            HStack(spacing: 4) {
                Text("Map and routing data ©")
                Link(
                    "OpenStreetMap contributors",
                    destination: URL(string: "https://www.openstreetmap.org/copyright")!
                )
            }

            HStack(spacing: 4) {
                Link("Search by Photon", destination: URL(string: "https://photon.komoot.io/")!)
                Text("·")
                Link("Routing by OSRM", destination: URL(string: "https://project-osrm.org/")!)
            }

            Text("Wet risk is an estimate, not a guarantee.")
                .padding(.top, 2)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}
