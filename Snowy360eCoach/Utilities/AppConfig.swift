import Foundation

// MARK: - Configuration
// Centralized app configuration. Tokens are loaded from environment/keychain at runtime.

enum AppConfig {
    // GitHub Models API
    static var githubToken: String {
        // In production: load from Keychain
        // For development: set via environment variable or plist
        ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ""
    }

    static let githubModelsEndpoint = "https://models.github.ai/inference/chat/completions"

    // Frame sampling
    static let defaultFrameInterval: TimeInterval = 3.0        // seconds between frames
    static let burstFrameInterval: TimeInterval = 1.5           // during detected turns
    static let maxFramesPerMinute = 20                          // rate limit: 20 req/min for low-tier models

    // Image compression
    static let frameMaxWidth: CGFloat = 512
    static let frameJPEGQuality: CGFloat = 0.6

    // Camera heartbeat
    static let heartbeatInterval: TimeInterval = 0.5            // CRITICAL: camera disconnects after 30s without

    // Voice
    static let speechRate: Float = 1.2                          // Slightly faster TTS
    static let speechLanguage = "zh-CN"

    // Session
    static let maxConversationHistory = 12                      // Keep last N messages for context
    static let maxFeedbackDisplay = 50                          // Max feedback items shown in UI
}
