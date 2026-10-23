import SwiftUI

struct BestDepartureCard: View {
    let plan: DeparturePlan
    let onUse: () -> Void

    var body: some View {
        CardContainer {
            if plan.shouldWait {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Better window ahead", systemImage: "sun.max.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.safe)

                    Text("Leave at \(plan.bestDeparture.formatted(.dateTime.hour().minute()))")
                        .font(.title2.bold())

                    Text("\(plan.best.roundedWetPercent)% wet — \(plan.segmentsSaved) fewer wet \(plan.segmentsSaved == 1 ? "segment" : "segments") than leaving now (\(plan.now.roundedWetPercent)%).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onUse) {
                        Label("Use this time", systemImage: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.safe)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Leaving now is as good as it gets")
                            .font(.headline)
                        if plan.now.wetSegmentCount == 0 {
                            Text("The route looks dry at every departure in the next four hours.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No departure in the next four hours removes a wet segment.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}
