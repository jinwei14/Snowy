import Foundation
import UIKit

// MARK: - AI Coaching Service (GitHub Models API)

final class AICoachingService {
    private let endpoint = URL(string: "https://models.github.ai/inference/chat/completions")!
    private let token: String
    private let session: URLSession

    /// Model IDs on GitHub Models
    enum Model: String {
        case gpt4_1_mini = "openai/gpt-4.1-mini"   // Fast — real-time coaching
        case gpt4o_mini  = "openai/gpt-4o-mini"     // Alternative fast
        case gpt4o       = "openai/gpt-4o"           // High quality — post-session
        case gpt4_1      = "openai/gpt-4.1"          // Alternative high quality
    }

    init(githubToken: String) {
        self.token = githubToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Real-Time Frame Analysis (Streaming)

    /// Analyze a single frame with streaming response for minimum latency.
    /// Returns an AsyncStream of text tokens as they arrive from the API.
    func analyzeFrame(
        image: UIImage,
        systemPrompt: String,
        conversationHistory: [ChatMessage] = [],
        model: Model = .gpt4_1_mini
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let base64 = ImageCompressor.compressForUpload(image)
                    var messages: [[String: Any]] = [
                        ["role": "system", "content": systemPrompt]
                    ]

                    // Add conversation history for context
                    for msg in conversationHistory.suffix(6) {
                        messages.append(["role": msg.role, "content": msg.content])
                    }

                    // Add current frame
                    messages.append([
                        "role": "user",
                        "content": [
                            ["type": "image_url", "image_url": [
                                "url": "data:image/jpeg;base64,\(base64)",
                                "detail": "low"
                            ]],
                            ["type": "text", "text": "分析这一帧，给出教练建议。"]
                        ] as [[String: Any]]
                    ])

                    let request = try self.buildStreamingRequest(messages: messages, model: model)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AICoachingError.invalidResponse)
                        return
                    }

                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: AICoachingError.rateLimited)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: AICoachingError.httpError(httpResponse.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }

                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Multi-Frame Analysis (3-frame context for motion)

    /// Send 3 frames with timestamps to show motion through a turn.
    func analyzeMultiFrame(
        frames: [(image: UIImage, label: String)],
        systemPrompt: String,
        model: Model = .gpt4_1_mini
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [[String: Any]] = [
                        ["role": "system", "content": systemPrompt]
                    ]

                    var contentParts: [[String: Any]] = []
                    for (index, frame) in frames.enumerated() {
                        let base64 = ImageCompressor.compressForUpload(frame.image)
                        contentParts.append([
                            "type": "text",
                            "text": "帧 \(index + 1) (\(frame.label)):"
                        ])
                        contentParts.append([
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64)",
                                "detail": "low"
                            ] as [String: Any]
                        ])
                    }
                    contentParts.append([
                        "type": "text",
                        "text": "分析这\(frames.count)帧，告诉骑手这个弯做得如何。"
                    ])

                    messages.append([
                        "role": "user",
                        "content": contentParts
                    ])

                    let request = try self.buildStreamingRequest(messages: messages, model: model)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: AICoachingError.httpError(code))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }

                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Reference Video Pre-Analysis (Non-streaming, GPT-4o)

    /// Deep analysis of reference video key frames. Returns structured JSON.
    func analyzeReferenceVideo(
        keyFrames: [(image: UIImage, timestamp: TimeInterval)],
        technique: TechniqueCategory
    ) async throws -> ReferenceProfile {
        var contentParts: [[String: Any]] = []

        for (index, frame) in keyFrames.enumerated() {
            let base64 = ImageCompressor.compressForUpload(frame.image, quality: 0.8)
            contentParts.append([
                "type": "text",
                "text": "关键帧 \(index + 1) (时间: \(String(format: "%.1f", frame.timestamp))秒):"
            ])
            contentParts.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)",
                    "detail": "high"
                ] as [String: Any]
            ])
        }

        contentParts.append([
            "type": "text",
            "text": """
            这是一个\(technique.displayName)的参考视频关键帧。请深度分析并返回以下JSON格式：
            {
              "edgeTimingDescription": "入刃时机描述",
              "angulationLevel": "折叠程度描述",
              "edgeAngleDescription": "立刃角度描述",
              "rotationDescription": "旋转幅度描述",
              "overallDescription": "整体技术总结",
              "keyPoints": ["要点1", "要点2", ...]
            }
            只返回JSON，不要其他文字。
            """
        ])

        let messages: [[String: Any]] = [
            ["role": "system", "content": SystemPrompts.referenceAnalysis],
            ["role": "user", "content": contentParts]
        ]

        let request = try buildNonStreamingRequest(messages: messages, model: .gpt4o)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AICoachingError.httpError(code)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AICoachingError.invalidResponse
        }

        // Parse the JSON response into ReferenceProfile
        guard let profileData = content.data(using: .utf8),
              let profile = try? JSONDecoder().decode(ReferenceProfile.self, from: profileData) else {
            throw AICoachingError.parseError
        }

        return profile
    }

    // MARK: - Post-Session Summary (GPT-4o)

    func generateSessionSummary(
        feedbackLog: [FeedbackEntry],
        mountMode: CameraMountMode,
        duration: TimeInterval,
        referenceProfile: ReferenceProfile?
    ) async throws -> SessionSummary {
        let logText = feedbackLog.map { "[\($0.type.rawValue)] \($0.text)" }.joined(separator: "\n")

        var prompt = """
        训练时长: \(Int(duration / 60))分钟
        安装模式: \(mountMode.displayName)
        教练反馈记录:
        \(logText)
        """

        if let ref = referenceProfile {
            prompt += "\n\n参考视频技术基准:\n\(ref.promptDescription)"
        }

        prompt += """

        请生成训练总结，返回以下JSON格式：
        {
          "overallAssessment": "整体评价",
          "strengths": ["优点1", "优点2"],
          "areasForImprovement": ["改进点1", "改进点2"],
          "comparisonSummary": "与参考视频对比总结（如无参考则为null）",
          "nextSessionFocus": ["下次重点1", "下次重点2"],
          "technicalScores": {
            "edgeTiming": 75,
            "angulation": 60,
            "edgeAngle": 70,
            "rotation": 65,
            "balance": 80,
            "overall": 70
          }
        }
        只返回JSON。
        """

        let messages: [[String: Any]] = [
            ["role": "system", "content": SystemPrompts.sessionSummary],
            ["role": "user", "content": prompt]
        ]

        let request = try buildNonStreamingRequest(messages: messages, model: .gpt4o)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AICoachingError.httpError(code)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let summaryData = content.data(using: .utf8),
              let summary = try? JSONDecoder().decode(SessionSummary.self, from: summaryData) else {
            throw AICoachingError.parseError
        }

        return summary
    }

    // MARK: - Conversational Response (rider asks a question)

    func answerQuestion(
        question: String,
        systemPrompt: String,
        recentImage: UIImage?,
        conversationHistory: [ChatMessage] = []
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var messages: [[String: Any]] = [
                        ["role": "system", "content": systemPrompt]
                    ]

                    for msg in conversationHistory.suffix(10) {
                        messages.append(["role": msg.role, "content": msg.content])
                    }

                    if let image = recentImage {
                        let base64 = ImageCompressor.compressForUpload(image)
                        messages.append([
                            "role": "user",
                            "content": [
                                ["type": "image_url", "image_url": [
                                    "url": "data:image/jpeg;base64,\(base64)",
                                    "detail": "low"
                                ]],
                                ["type": "text", "text": question]
                            ] as [[String: Any]]
                        ])
                    } else {
                        messages.append(["role": "user", "content": question])
                    }

                    let request = try self.buildStreamingRequest(messages: messages, model: .gpt4_1_mini)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: AICoachingError.httpError(code))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }

                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildStreamingRequest(messages: [[String: Any]], model: Model) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "stream": true,
            "max_tokens": 200,   // Keep coaching responses short
            "temperature": 0.7,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildNonStreamingRequest(messages: [[String: Any]], model: Model) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "stream": false,
            "max_tokens": 2000,
            "temperature": 0.5,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Chat Message (for conversation history)

struct ChatMessage {
    let role: String    // "user", "assistant", "system"
    let content: String
}

// MARK: - Errors

enum AICoachingError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case rateLimited
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:       return "AI 返回了无效的响应"
        case .httpError(let code):   return "AI 请求失败 (HTTP \(code))"
        case .rateLimited:           return "API 请求过于频繁，请稍后再试"
        case .parseError:            return "无法解析 AI 响应"
        }
    }
}
