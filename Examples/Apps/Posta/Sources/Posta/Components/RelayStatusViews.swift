import SwiftUI
import NDKSwift

// MARK: - Connection Status Badge
/// A reusable view that displays relay connection status with both visual indicator and text
public struct ConnectionStatusBadge: View {
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
            .background(statusColor.opacity(0.2))
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
        }
    }
}

// MARK: - Relay Row View
/// A row view for displaying relay information with connection status
public struct RelayRowView: View {
    let url: String
    let state: NDKRelayConnectionState
    let lastSeen: Date?
    
    public init(url: String, state: NDKRelayConnectionState, lastSeen: Date? = nil) {
        self.url = url
        self.state = state
        self.lastSeen = lastSeen
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
            
            ConnectionStatusBadge(state: state, style: .full)
        }
        .padding(.vertical, 4)
    }
    
    private var displayUrl: String {
        url.replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - Relay Stats View
/// A view that displays relay statistics and health information
public struct RelayStatsView: View {
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
            ConnectionHealthBar(
                connected: connectedRelays,
                total: totalRelays
            )
        }
        .padding()
        .background(Color(.secondarySystemBackground))
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

// MARK: - Connection Health Bar
/// A visual indicator of relay connection health
struct ConnectionHealthBar: View {
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
    
    var body: some View {
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
                        .fill(Color(.systemGray5))
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