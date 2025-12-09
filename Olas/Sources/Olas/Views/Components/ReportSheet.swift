// ReportSheet.swift
import SwiftUI
import NDKSwift

struct ReportSheet: View {
    let event: NDKEvent
    let ndk: NDK
    @Environment(\.dismiss) private var dismiss

    @State private var isSubmitting = false
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(OlasConstants.ReportType.allCases) { type in
                        Button {
                            Task { await submitReport(type: type) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.displayName)
                                        .foregroundStyle(.primary)
                                    Text(type.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isSubmitting {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSubmitting)
                    }
                } header: {
                    Text("Select a reason")
                } footer: {
                    Text("Reports are sent to relay operators who may take action based on their policies.")
                }
            }
            .navigationTitle("Report Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Report Submitted", isPresented: $showConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you for helping keep the community safe.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submitReport(type: OlasConstants.ReportType) async {
        isSubmitting = true

        do {
            _ = try await ndk.publish { builder in
                builder
                    .kind(OlasConstants.EventKinds.report)
                    .content("")
                    .tag(["e", event.id, type.rawValue])
                    .tag(["p", event.pubkey, type.rawValue])
            }
            showConfirmation = true
        } catch {
            // Dismiss on error too - report was attempted
            dismiss()
        }

        isSubmitting = false
    }
}
