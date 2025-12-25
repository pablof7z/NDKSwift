import Foundation
import NDKSwiftCore

/// Global service for capturing NDK logs that persists across view navigation.
/// Enable once, and logs are captured until explicitly disabled.
@Observable
@MainActor
public final class LogCaptureService {
    public static let shared = LogCaptureService()

    private(set) var messages: [String] = []
    private(set) var isCapturing: Bool = false

    private let maxMessages = 500
    private let isCapturingKey = "logCaptureEnabled"

    private init() {
        // Restore previous capturing state
        if UserDefaults.standard.bool(forKey: isCapturingKey) {
            startCapturing()
        }
    }

    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        UserDefaults.standard.set(true, forKey: isCapturingKey)

        NDKLogger.setLogHandler { [weak self] message in
            Task { @MainActor in
                self?.appendMessage(message)
            }
        }
    }

    func stopCapturing() {
        guard isCapturing else { return }
        isCapturing = false
        UserDefaults.standard.set(false, forKey: isCapturingKey)
        NDKLogger.setLogHandler(nil)
    }

    func clearMessages() {
        messages.removeAll()
    }

    private func appendMessage(_ message: String) {
        messages.append(message)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
