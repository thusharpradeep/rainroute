import SwiftUI
import UIKit

struct GoogleMapsImportSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var errorMessage: String?
    @FocusState private var isLinkFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instructions
                    linkEditor
                    pasteButton
                    importButton
                    if let errorMessage {
                        errorCard(errorMessage)
                    }
                    geometryNote
                }
                .padding(18)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Import from Google Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste a directions link")
                .font(.headline)

            Text("In Google Maps, choose your start, destination, and any stops. Tap Share, then Copy link. Paste that link here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FeatureRow(
                icon: "location.fill",
                text: "RainRoute uses the link's start, destination, and stops."
            )
            FeatureRow(
                icon: "arrow.triangle.swap",
                text: "It then finds the driving route again with OSRM, so the roads can differ slightly from Google's."
            )
        }
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Google Maps link")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "https://maps.app.goo.gl/…",
                text: $link,
                axis: .vertical
            )
            .lineLimit(3...5)
            .focused($isLinkFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .padding(12)
            .background(
                Theme.elevated,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isLinkFocused ? Theme.accent.opacity(0.55) : Theme.hairline.opacity(0.5),
                        lineWidth: isLinkFocused ? 1.5 : 0.5
                    )
            )
        }
    }

    private var pasteButton: some View {
        Button {
            if let pasted = UIPasteboard.general.string {
                link = pasted
            }
        } label: {
            Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private var importButton: some View {
        Button {
            isLinkFocused = false
            Task { @MainActor in
                await importLink()
            }
        } label: {
            HStack(spacing: 8) {
                if model.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(model.isImporting ? "Importing…" : "Import route")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                Theme.accent.opacity(canImport ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canImport)
    }

    private var geometryNote: some View {
        Text("Google does not include its exact road geometry in a share link. RainRoute imports the stops and routes between them with OSRM. Add via-stops in Google Maps to pin the corridor you want.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .font(.caption)
                .padding(.top, 2)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.caution.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    private var canImport: Bool {
        !model.isImporting
            && !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func importLink() async {
        errorMessage = nil
        do {
            try await model.importGoogleMapsLink(link, settings: settings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
