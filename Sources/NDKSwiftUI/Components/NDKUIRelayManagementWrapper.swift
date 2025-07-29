import SwiftUI
import NDKSwift

/// A convenience wrapper for NDKUIRelayManagementView that handles common initialization patterns
public struct NDKUIRelayManagementWrapper: View {
    @Environment(\.ndk) private var ndk: NDK?
    
    public init() {}
    
    public var body: some View {
        Group {
            if let ndk = ndk {
                NDKUIRelayManagementView(ndk: ndk)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)
                    Text("NDK not initialized")
                        .font(.headline)
                    Text("Please log in to manage relays")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Relay Management")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}