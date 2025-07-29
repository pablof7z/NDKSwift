import SwiftUI
import NDKSwift

// MARK: - NDKUIConnectionStatusBadge
/// A reusable view that displays relay connection status with both visual indicator and text
public struct NDKUIConnectionStatusBadge: View {
    let state: NDKRelayConnectionState
    let style: BadgeStyle
    
    public enum BadgeStyle {
        case full        // Shows dot + text + background
        case compact     // Shows only dot
        case text        // Shows only text
    }
    
    public init(state: NDKRelayConnectionState, style: BadgeStyle = .full) {
        self.state = state
        self.style = style
    }
    
    public var body: some View {
        switch style {
        case .full:
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(OpacityConstants.lightBackground))
            .cornerRadius(12)
            
        case .compact:
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
                
        case .text:
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
    }
    
    private var statusColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .disconnecting:
            return .orange
        case .failed:
            return .red
        case .authRequired:
            return .yellow
        case .authenticating:
            return .orange
        case .authenticated:
            return .green
        @unknown default:
            return .gray
        }
    }
    
    private var statusText: String {
        switch state {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .disconnecting:
            return "Disconnecting"
        case .failed:
            return "Failed"
        case .authRequired:
            return "Auth Required"
        case .authenticating:
            return "Authenticating"
        case .authenticated:
            return "Authenticated"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - NDKUIRelayRowView
/// A row view for displaying relay information with connection status
public struct NDKUIRelayRowView: View {
    let url: String
    let state: NDKRelayConnectionState
    let lastSeen: Date?
    let showDeleteButton: Bool
    let onDelete: (() -> Void)?
    
    public init(
        url: String, 
        state: NDKRelayConnectionState, 
        lastSeen: Date? = nil,
        showDeleteButton: Bool = false,
        onDelete: (() -> Void)? = nil
    ) {
        self.url = url
        self.state = state
        self.lastSeen = lastSeen
        self.showDeleteButton = showDeleteButton
        self.onDelete = onDelete
    }
    
    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayUrl)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                
                if let lastSeen = lastSeen {
                    Text("Last seen \(lastSeen, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            NDKUIConnectionStatusBadge(state: state, style: .full)
            
            if showDeleteButton, let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }
    
    private var displayUrl: String {
        url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - NDKUIRelayStatsView
/// A view that displays relay statistics and health information
public struct NDKUIRelayStatsView: View {
    let totalRelays: Int
    let connectedRelays: Int
    let pendingMessages: Int
    
    public init(totalRelays: Int, connectedRelays: Int, pendingMessages: Int = 0) {
        self.totalRelays = totalRelays
        self.connectedRelays = connectedRelays
        self.pendingMessages = pendingMessages
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Connection summary
            HStack(spacing: 24) {
                StatItem(
                    title: "Total",
                    value: "\(totalRelays)",
                    color: .primary
                )
                
                StatItem(
                    title: "Connected",
                    value: "\(connectedRelays)",
                    color: connectedRelays > 0 ? .green : .red
                )
                
                if pendingMessages > 0 {
                    StatItem(
                        title: "Pending",
                        value: "\(pendingMessages)",
                        color: .orange
                    )
                }
            }
            
            // Connection health indicator
            NDKUIConnectionHealthBar(
                connected: connectedRelays,
                total: totalRelays
            )
        }
        .padding()
        .background(Color.ndkSecondaryBackground)
        .cornerRadius(12)
    }
    
    struct StatItem: View {
        let title: String
        let value: String
        let color: Color
        
        var body: some View {
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - NDKUIConnectionHealthBar
/// A visual indicator of relay connection health
public struct NDKUIConnectionHealthBar: View {
    let connected: Int
    let total: Int
    
    private var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(connected) / Double(total)
    }
    
    private var healthColor: Color {
        switch percentage {
        case 0.8...1.0:
            return .green
        case 0.5..<0.8:
            return .orange
        default:
            return .red
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Connection Health")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(percentage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(healthColor)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.ndkGray5)
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(healthColor)
                        .frame(width: geometry.size.width * percentage, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - NDKUIRelayIconView
/// A reusable view that displays a relay icon with fallback
public struct NDKUIRelayIconView: View {
    let icon: Image?
    let size: CGFloat
    
    public init(icon: Image? = nil, size: CGFloat = 40) {
        self.icon = icon
        self.size = size
    }
    
    public var body: some View {
        Group {
            if let icon = icon {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.6))
                    .foregroundColor(.blue)
                    .frame(width: size, height: size)
                    .background(Color.blue.opacity(OpacityConstants.lightBackground))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            }
        }
    }
}

// MARK: - NDKUIRelayInfoView
/// A view that displays NIP-11 information for a relay
public struct NDKUIRelayInfoView: View {
    let info: NDKRelayInformation
    let style: InfoStyle
    
    public enum InfoStyle {
        case compact    // Just software/version
        case full       // All available info
    }
    
    public init(info: NDKRelayInformation, style: InfoStyle = .compact) {
        self.info = info
        self.style = style
    }
    
    public var body: some View {
        switch style {
        case .compact:
            VStack(alignment: .trailing, spacing: 2) {
                if let software = info.software {
                    Text(software)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let version = info.version {
                    Text(version)
                        .font(.caption2)
                        .foregroundColor(Color.secondary.opacity(OpacityConstants.dimmed))
                }
            }
            
        case .full:
            VStack(alignment: .leading, spacing: 8) {
                if let name = info.name {
                    LabeledContent("Name", value: name)
                }
                if let description = info.description {
                    LabeledContent("Description", value: description)
                }
                if let software = info.software {
                    LabeledContent("Software", value: software)
                }
                if let version = info.version {
                    LabeledContent("Version", value: version)
                }
                if let contact = info.contact {
                    LabeledContent("Contact", value: contact)
                }
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct NDKUIRelayStatusViews_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            NDKUIConnectionStatusBadge(state: .connected, style: .full)
            NDKUIConnectionStatusBadge(state: .connecting, style: .compact)
            NDKUIConnectionStatusBadge(state: .failed("Connection error"), style: .text)
            
            NDKUIRelayRowView(
                url: "wss://relay.damus.io",
                state: .connected,
                lastSeen: Date()
            )
            
            NDKUIRelayStatsView(
                totalRelays: 8,
                connectedRelays: 6,
                pendingMessages: 3
            )
        }
        .padding()
    }
}
#endif