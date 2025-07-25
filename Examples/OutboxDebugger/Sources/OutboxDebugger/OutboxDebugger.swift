import Foundation
import NDKSwift

@main
struct OutboxDebugger {
    static func main() async {
        // Disable NDK's built-in logging
        NDKLogger.isEnabled = false
        
        let debugger = DebuggerCLI()
        await debugger.run()
    }
}

actor DebuggerCLI {
    private let ndk: NDK
    private let relayMonitor = RelayMonitor()
    private let renderer = TerminalRenderer()
    private let commandProcessor: CommandProcessor
    
    private var isRunning = true
    private var inputBuffer = ""
    private var commandHistory: [String] = []
    private var historyIndex = -1
    
    init() {
        // Generate private key
        let signer = try! NDKPrivateKeySigner.generate()
        
        // Configure NDK with relay
        self.ndk = NDK(
            relayUrls: ["wss://relay.primal.net"],
            signer: signer
        )
        
        // Create command processor first
        self.commandProcessor = CommandProcessor(ndk: ndk, signer: signer)
        
        // Set up combined relay activity hook that handles both relay monitoring and command processor needs
        NDKRelayConnection.setActivityHook { [weak self] url, event in
            guard let self = self else { return }
            
            // Update relay monitor
            await self.relayMonitor.updateRelayStatus(
                url: url.absoluteString,
                status: self.mapEventToStatus(event)
            )
            
            switch event {
            case .messageSent:
                await self.relayMonitor.incrementSentEvents(url: url.absoluteString)
            case .messageReceived:
                await self.relayMonitor.incrementReceivedEvents(url: url.absoluteString)
            case let .eventPublished(eventId, accepted, message):
                // Track OK responses for command processor
                await self.commandProcessor.trackPublishResult(
                    eventId: eventId,
                    relay: url.absoluteString,
                    accepted: accepted,
                    message: message
                )
            default:
                break
            }
            
            await self.renderer.updateRelayStatus(await self.relayMonitor.getAllStats())
        }
    }
    
    func run() async {
        // Connect to relay
        await renderer.render(inputBuffer: "", output: "Connecting to relay.primal.net...")
        await ndk.connect()
        
        // Wait for connection
        await renderer.render(inputBuffer: "", output: "Waiting for relay connection...")
        
        // Wait a bit for connections to establish
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        let (connectedCount, _) = await ndk.getRelayConnectionSummary()
        
        if connectedCount == 0 {
            await renderer.render(inputBuffer: "", output: Terminal.color("⚠️ Warning: No relays connected! Commands may hang.\n\nTry waiting a moment or check your internet connection.", .yellow))
            try? await Task.sleep(nanoseconds: 2_000_000_000) // Show warning for 2s
        }
        
        // Set up terminal
        Terminal.setRawMode()
        Terminal.hideCursor()
        Terminal.clear()
        
        // Initial render
        await renderer.render(inputBuffer: inputBuffer, output: "Welcome to Outbox Debugger! Type 'help' for commands.")
        await renderer.updateRelayStatus(await relayMonitor.getAllStats())
        
        // Start input loop
        await inputLoop()
        
        // Cleanup
        Terminal.showCursor()
        Terminal.restoreMode()
        Terminal.clear()
    }
    
    private func inputLoop() async {
        while isRunning {
            guard let char = readChar() else {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                continue
            }
            
            switch char {
            case "\u{7F}", "\u{08}": // Backspace
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                    await renderer.render(inputBuffer: inputBuffer, output: nil)
                }
                
            case "\r", "\n": // Enter
                if !inputBuffer.isEmpty {
                    let command = inputBuffer
                    inputBuffer = ""
                    commandHistory.append(command)
                    historyIndex = -1
                    
                    // For long-running commands, show progress
                    if command.starts(with: "req") || command.starts(with: "publish") {
                        await renderer.render(inputBuffer: inputBuffer, output: "Processing: \(command)\n\nConnecting to relays...")
                        
                        // Give visual feedback that something is happening
                        Task {
                            var dots = 0
                            while true {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                                dots = (dots + 1) % 4
                                let dotString = String(repeating: ".", count: dots)
                                await renderer.render(inputBuffer: inputBuffer, output: "Processing: \(command)\n\nConnecting to relays\(dotString)")
                            }
                        }
                    } else {
                        await renderer.render(inputBuffer: inputBuffer, output: "Processing: \(command)")
                    }
                    
                    let output = await processCommand(command)
                    await renderer.render(inputBuffer: inputBuffer, output: output)
                }
                
            case "\u{1B}": // Escape sequences
                if let next = readChar(), next == "[" {
                    if let arrow = readChar() {
                        switch arrow {
                        case "A": // Up arrow
                            if commandHistory.count > 0 {
                                if historyIndex == -1 {
                                    historyIndex = commandHistory.count - 1
                                } else if historyIndex > 0 {
                                    historyIndex -= 1
                                }
                                inputBuffer = commandHistory[historyIndex]
                                await renderer.render(inputBuffer: inputBuffer, output: nil)
                            }
                        case "B": // Down arrow
                            if historyIndex >= 0 && historyIndex < commandHistory.count - 1 {
                                historyIndex += 1
                                inputBuffer = commandHistory[historyIndex]
                                await renderer.render(inputBuffer: inputBuffer, output: nil)
                            } else if historyIndex == commandHistory.count - 1 {
                                historyIndex = -1
                                inputBuffer = ""
                                await renderer.render(inputBuffer: inputBuffer, output: nil)
                            }
                        default:
                            break
                        }
                    }
                }
                
            case "\u{03}": // Ctrl+C
                isRunning = false
                
            default:
                if char.isPrintable {
                    inputBuffer.append(char)
                    await renderer.render(inputBuffer: inputBuffer, output: nil)
                }
            }
        }
    }
    
    private func readChar() -> Character? {
        var buffer = [UInt8](repeating: 0, count: 1)
        let bytesRead = read(STDIN_FILENO, &buffer, 1)
        
        if bytesRead > 0 {
            return Character(UnicodeScalar(buffer[0]))
        }
        return nil
    }
    
    private func processCommand(_ command: String) async -> String {
        let parts = command.split(separator: " ")
        guard let cmd = parts.first?.lowercased() else {
            return "Empty command"
        }
        
        switch cmd {
        case "help":
            return """
            Available commands:
              outbox [npub]     - Show outbox information for npub
              publish npub...   - Create kind:1 event tagging npubs
              req npub...       - Fetch recent kind:1 from npubs
              clear             - Clear the screen
              exit              - Exit the debugger
            """
            
        case "clear":
            Terminal.clear()
            await renderer.render(inputBuffer: inputBuffer, output: "Screen cleared")
            return ""
            
        case "exit":
            isRunning = false
            return "Goodbye!"
            
        case "outbox":
            let npubs = Array(parts.dropFirst()).map(String.init)
            return await commandProcessor.processOutbox(npubs: npubs)
            
        case "publish":
            let npubs = Array(parts.dropFirst()).map(String.init)
            let stats = await relayMonitor.getAllStats()
            return await commandProcessor.processPublish(npubs: npubs, relayStats: stats)
            
        case "req":
            let npubs = Array(parts.dropFirst()).map(String.init)
            return await commandProcessor.processReq(npubs: npubs)
            
        default:
            return "Unknown command: \(cmd). Type 'help' for available commands."
        }
    }
    
    private func mapEventToStatus(_ event: NDKRelayConnection.RelayActivityEvent) -> RelayMonitor.RelayStatus {
        switch event {
        case .connected:
            return .connected
        case .disconnected(let error):
            if let error = error {
                return .error(error.localizedDescription)
            }
            return .disconnected
        default:
            return .connected
        }
    }
}

extension Character {
    var isPrintable: Bool {
        let scalar = self.unicodeScalars.first!
        return scalar.value >= 32 && scalar.value < 127
    }
}