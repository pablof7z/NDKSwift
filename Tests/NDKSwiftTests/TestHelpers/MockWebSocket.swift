import Foundation
@testable import NDKSwift

// Mock WebSocket for testing relay connections
class MockWebSocket {
    var sentMessages: [String] = []
    var mockResponses: [String] = []
    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onMessage: ((String) -> Void)?
    
    private var responseTimer: Timer?
    private var responseIndex = 0
    
    func connect() {
        isConnected = true
        onConnect?()
    }
    
    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        isConnected = false
        responseTimer?.invalidate()
        responseTimer = nil
        onDisconnect?(nil)
    }
    
    func send(text: String) async throws {
        guard isConnected else {
            throw WebSocketError.notConnected
        }
        sentMessages.append(text)
        
        // Simulate async response if configured
        if !mockResponses.isEmpty && responseIndex < mockResponses.count {
            let response = mockResponses[responseIndex]
            responseIndex += 1
            
            // Simulate network delay
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            onMessage?(response)
        }
    }
    
    func send(data: Data) async throws {
        // Convert data to string for testing
        if let text = String(data: data, encoding: .utf8) {
            try await send(text: text)
        }
    }
    
    // Helper methods for testing
    func simulateMessage(_ message: String) {
        guard isConnected else { return }
        onMessage?(message)
    }
    
    func simulateMessages(_ messages: [String], delay: TimeInterval = 0.01) {
        guard isConnected else { return }
        
        var index = 0
        responseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: true) { [weak self] timer in
            guard let self = self, self.isConnected, index < messages.count else {
                timer.invalidate()
                return
            }
            
            self.onMessage?(messages[index])
            index += 1
        }
    }
    
    func simulateDisconnect(error: Error? = nil) {
        isConnected = false
        responseTimer?.invalidate()
        responseTimer = nil
        onDisconnect?(error)
    }
    
    func clearSentMessages() {
        sentMessages.removeAll()
    }
    
    func getLastSentMessage() -> String? {
        sentMessages.last
    }
    
    func getSentMessage(at index: Int) -> String? {
        guard index < sentMessages.count else { return nil }
        return sentMessages[index]
    }
}

enum WebSocketError: Error {
    case notConnected
    case invalidMessage
    case connectionFailed
}