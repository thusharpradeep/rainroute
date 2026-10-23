import SwiftUI

struct JourneySearchCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let onImport: () -> Void
    @FocusState private var focusedField: AppModel.Field?

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Where are you riding?")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.swapEndpoints()
                        focusedField = nil
                    } label: {
                        Label("Swap start and destination", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap start and destination")
                    .disabled(model.isRiding)
                }

                VStack(spacing: 10) {
                    searchRow(
                        field: .start,
                        title: "Start",
                        placeholder: "Type a starting town or landmark",
                        icon: "circle.fill",
                        tint: Theme.accent
                    )
                    searchRow(
                        field: .destination,
                        title: "Destination",
                        placeholder: "Type where you are going",
                        icon: "mappin.circle.fill",
                        tint: Theme.heavyRain
                    )
                }
                .disabled(model.isRiding)

                if model.isShowingSuggestions {
                    suggestionsList
                }

                if model.isSearchingPlaces && !model.isShowingSuggestions {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching places…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(model.isLoading ? "Checking…" : "Check the route")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent.opacity(model.canCheck ? 1 : 0.35))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!model.canCheck)

                Button(action: onImport) {
                    Label("Import from Google Maps", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Theme.accent)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isLoading || model.isImporting || model.isRiding)

                if model.routeSource == .googleMaps {
                    importedRouteBanner
                }

                if model.isLoading, let status = model.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .onChange(of: focusedField) { _, newValue in
            if let newValue {
                model.beginEditing(newValue)
            } else {
                model.endEditing()
            }
        }
    }

    @ViewBuilder
    private func searchRow(
        field: AppModel.Field,
        title: String,
        placeholder: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    placeholder,
                    text: Binding(
                        get: { model.query(for: field) },
                        set: { model.updateQuery($0, for: field) }
                    )
                )
                .focused($focusedField, equals: field)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(field == .start ? .next : .go)
                .onSubmit {
                    if field == .start {
                        focusedField = .destination
                    } else {
                        submit()
                    }
                }
            }

            if !model.query(for: field).isEmpty {
                Button {
                    model.clear(field)
                    focusedField = field
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title.lowercased())")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.background.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    focusedField == field ? Theme.accent.opacity(0.55) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    private var importedRouteBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.safe)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(importedRouteText)
                    .font(.caption.weight(.semibold))
                Button("Use OSRM's default route") {
                    Task {
                        await model.clearImportedRoute(settings: settings)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .disabled(model.isLoading || model.isRiding)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.safe.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var importedRouteText: String {
        let count = model.importedStops.count
        if count == 0 {
            return "Imported from Google Maps"
        }
        return "Imported from Google Maps · \(count) \(count == 1 ? "stop" : "stops")"
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(model.suggestions) { place in
                Button {
                    choose(place)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let subtitle = place.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if place.id != model.suggestions.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.elevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.hairline.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func choose(_ place: Place) {
        guard let field = model.activeField else { return }
        model.select(place, for: field)
        focusedField = nil
    }

    private func submit() {
        focusedField = nil
        Task {
            await model.check(settings: settings)
        }
    }
}
