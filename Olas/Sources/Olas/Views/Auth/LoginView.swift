import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nsec = ""
    @State private var showError = false
    @State private var errorMessage = ""

    public init(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter your private key (nsec)")
                    .font(.headline)

                SecureField("nsec1...", text: $nsec)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(OlasTheme.Colors.deepTeal)
                    Text("Your key stays on device and is never sent anywhere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        do {
                            try await authViewModel.loginWithNsec(nsec)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                } label: {
                    if authViewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(OlasTheme.Colors.deepTeal)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(nsec.isEmpty || authViewModel.isLoading)

                Button("Paste from clipboard") {
                    pasteFromClipboard()
                }
                .font(.subheadline)
                .foregroundStyle(OlasTheme.Colors.oceanBlue)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Connect Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Login Failed", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        if let clipboardContent = UIPasteboard.general.string {
            nsec = clipboardContent
        }
        #elseif os(macOS)
        if let clipboardContent = NSPasteboard.general.string(forType: .string) {
            nsec = clipboardContent
        }
        #endif
    }
}
