import Foundation

actor TerminalRenderer {
    private var lastRelayStatus: String = ""
    private var lastOutput: String = ""
    
    func render(inputBuffer: String, output: String?) {
        if let output = output {
            lastOutput = output
        }
        
        let (width, height) = Terminal.getTerminalSize()
        
        Terminal.clear()
        
        // Draw border
        drawBorder(width: width, height: height)
        
        // Draw relay status in top-right
        if !lastRelayStatus.isEmpty {
            let statusLines = lastRelayStatus.split(separator: "\n")
            for (index, line) in statusLines.enumerated() {
                Terminal.moveCursor(x: width - Int(line.count) - 2, y: index + 2)
                print(line, terminator: "")
            }
        }
        
        // Draw output
        let outputStartY = 5
        if !lastOutput.isEmpty {
            let outputLines = lastOutput.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in outputLines.enumerated() {
                if index + outputStartY < height - 4 {
                    Terminal.moveCursor(x: 3, y: outputStartY + index)
                    let maxWidth = width - 6
                    let truncated = String(line.prefix(maxWidth))
                    print(truncated, terminator: "")
                }
            }
        }
        
        // Draw input prompt
        Terminal.moveCursor(x: 3, y: height - 2)
        print(Terminal.color("❯ ", .brightGreen) + inputBuffer, terminator: "")
        
        // Position cursor
        Terminal.moveCursor(x: 5 + inputBuffer.count, y: height - 2)
        Terminal.showCursor()
        
        fflush(stdout)
    }
    
    func updateRelayStatus(_ stats: [RelayMonitor.RelayStats]) {
        var status = ""
        
        for stat in stats {
            let url = stat.url.replacingOccurrences(of: "wss://", with: "")
                             .replacingOccurrences(of: "ws://", with: "")
            
            let statusEmoji: String
            let statusColor: Terminal.Color
            
            switch stat.status {
            case .connecting:
                statusEmoji = "🟡"
                statusColor = .yellow
            case .connected:
                statusEmoji = "🟢"
                statusColor = .green
            case .disconnected:
                statusEmoji = "🔴"
                statusColor = .red
            case .error:
                statusEmoji = "⚠️"
                statusColor = .brightRed
            }
            
            let shortUrl = url.count > 20 ? String(url.prefix(17)) + "..." : url
            status += "\(statusEmoji) \(Terminal.color(shortUrl, statusColor)) "
            status += Terminal.dim("↑\(stat.sentEvents) ↓\(stat.receivedEvents)")
            status += "\n"
        }
        
        lastRelayStatus = status
    }
    
    private func drawBorder(width: Int, height: Int) {
        // Top border
        Terminal.moveCursor(x: 1, y: 1)
        print("┌" + String(repeating: "─", count: width - 2) + "┐", terminator: "")
        
        // Title
        let title = " Outbox Debugger "
        Terminal.moveCursor(x: (width - title.count) / 2, y: 1)
        print(Terminal.bold(Terminal.color(title, .brightCyan)), terminator: "")
        
        // Side borders
        for y in 2..<height {
            Terminal.moveCursor(x: 1, y: y)
            print("│", terminator: "")
            Terminal.moveCursor(x: width, y: y)
            print("│", terminator: "")
        }
        
        // Bottom border
        Terminal.moveCursor(x: 1, y: height)
        print("└" + String(repeating: "─", count: width - 2) + "┘", terminator: "")
    }
}