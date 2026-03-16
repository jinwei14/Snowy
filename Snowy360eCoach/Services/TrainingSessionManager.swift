import Foundation
import UIKit
import Combine

// MARK: - Training Session Manager
// The central orchestrator: connects camera → captures frames → sends to AI → speaks feedback.
// This is the "brain" of the app during an active training session.

@MainActor
final class TrainingSessionManager: ObservableObject {
    // Dependencies
    let cameraService: CameraService
    let aiService: AICoachingService
    let voiceService: VoiceService
    let motionService: MotionDetectionService
    private let sessionStorage = SessionStorage()

    // State
    @Published var trainingState: TrainingState = .idle
    @Published var currentSession: TrainingSession?
    @Published var feedbackHistory: [CoachingFeedback] = []
    @Published var isAnalyzing = false
    @Published var networkStatus: NetworkStatus = .good
    @Published var errorMessage: String?

    // Configuration
    var mountMode: CameraMountMode = .handheld
    var skillLevel: SkillLevel = .intermediate
    var activeReference: ReferenceVideo?
    var smartSamplingEnabled = true

    // Pipeline state
    private var analysisTask: Task<Void, Never>?
    private var frameBuffer: [TimestampedFrame] = []
    private let maxBufferSize = 3
    private var conversationHistory: [ChatMessage] = []
    private var currentSystemPrompt: String = ""
    private var isProcessingFrame = false
    private var frameDropCount = 0

    init(
        cameraService: CameraService,
        aiService: AICoachingService,
        voiceService: VoiceService,
        motionService: MotionDetectionService
    ) {
        self.cameraService = cameraService
        self.aiService = aiService
        self.voiceService = voiceService
        self.motionService = motionService
    }

    // MARK: - Training Lifecycle

    func startTraining() {
        guard cameraService.connectionState == .connected else {
            errorMessage = "请先连接相机"
            return
        }

        // Build system prompt based on configuration
        currentSystemPrompt = SystemPrompts.buildCoachingPrompt(
            mountMode: mountMode,
            referenceProfile: activeReference?.profile
        )

        // Create session
        currentSession = TrainingSession(
            mountMode: mountMode,
            skillLevel: skillLevel,
            referenceVideoId: activeReference?.id
        )

        feedbackHistory = []
        conversationHistory = []
        frameBuffer = []
        frameDropCount = 0
        trainingState = .active

        // Start all subsystems
        cameraService.startPreview()
        motionService.startMonitoring()

        // Start the frame analysis pipeline
        startAnalysisPipeline()

        addSystemFeedback("训练开始！\(mountMode.displayName)模式已激活")
    }

    func pauseTraining() {
        trainingState = .paused
        analysisTask?.cancel()
        voiceService.speak("训练已暂停")
    }

    func resumeTraining() {
        trainingState = .active
        startAnalysisPipeline()
        voiceService.speak("训练继续！")
    }

    func endTraining() {
        trainingState = .completed
        analysisTask?.cancel()
        cameraService.stopPreview()
        motionService.stopMonitoring()
        voiceService.stopSpeaking()

        currentSession?.end()

        if let session = currentSession {
            sessionStorage.save(session)
        }

        addSystemFeedback("训练结束！共分析 \(currentSession?.framesAnalyzed ?? 0) 帧")
    }

    // MARK: - Frame Analysis Pipeline

    private func startAnalysisPipeline() {
        analysisTask = Task { [weak self] in
            guard let self else { return }

            for await frame in self.cameraService.frameStream {
                guard !Task.isCancelled else { break }
                guard self.trainingState == .active else { continue }

                // Smart sampling: skip frames when rider is not doing anything interesting
                if self.smartSamplingEnabled && !self.motionService.isMoving && !self.motionService.isTurning {
                    continue
                }

                // Pipeline overlap: drop stale frames if we're still processing
                if self.isProcessingFrame {
                    self.frameDropCount += 1
                    continue
                }

                // Buffer frames for multi-frame context
                self.frameBuffer.append(TimestampedFrame(image: frame, timestamp: Date()))
                if self.frameBuffer.count > self.maxBufferSize {
                    self.frameBuffer.removeFirst()
                }

                await self.analyzeCurrentFrame(frame)
            }
        }
    }

    private func analyzeCurrentFrame(_ frame: UIImage) async {
        isProcessingFrame = true
        isAnalyzing = true
        defer {
            isProcessingFrame = false
            isAnalyzing = false
        }

        currentSession?.framesAnalyzed += 1
        var fullResponse = ""

        do {
            let stream = aiService.analyzeFrame(
                image: frame,
                systemPrompt: currentSystemPrompt,
                conversationHistory: conversationHistory,
                model: .gpt4_1_mini
            )

            for try await token in stream {
                fullResponse += token
                // Stream tokens directly to TTS for minimum latency
                voiceService.feedStreamingToken(token)
            }
            voiceService.flushSpeechBuffer()

            if !fullResponse.isEmpty {
                addAIFeedback(fullResponse)
                conversationHistory.append(ChatMessage(role: "assistant", content: fullResponse))

                // Keep conversation history manageable
                if conversationHistory.count > 12 {
                    conversationHistory.removeFirst(2)
                }
            }
            networkStatus = .good
        } catch {
            if let aiError = error as? AICoachingError {
                switch aiError {
                case .rateLimited:
                    networkStatus = .rateLimited
                    addSystemFeedback("API 频率受限，降低采样率")
                default:
                    networkStatus = .error
                }
            }
        }
    }

    // MARK: - Rider Voice Interaction

    func startListening() {
        do {
            try voiceService.startListening()
        } catch {
            errorMessage = "无法启动语音识别: \(error.localizedDescription)"
        }
    }

    func stopListeningAndAsk() {
        let question = voiceService.stopListening()
        guard !question.isEmpty else { return }

        addRiderFeedback(question)
        conversationHistory.append(ChatMessage(role: "user", content: question))

        Task {
            var fullResponse = ""
            let stream = aiService.answerQuestion(
                question: question,
                systemPrompt: currentSystemPrompt,
                recentImage: cameraService.latestFrame,
                conversationHistory: conversationHistory
            )

            do {
                for try await token in stream {
                    fullResponse += token
                    voiceService.feedStreamingToken(token)
                }
                voiceService.flushSpeechBuffer()

                if !fullResponse.isEmpty {
                    addAIFeedback(fullResponse, type: .aiAnswer)
                    conversationHistory.append(ChatMessage(role: "assistant", content: fullResponse))
                }
            } catch {
                addSystemFeedback("回答问题时出错")
            }
        }
    }

    // MARK: - Post-Session Summary

    func generateSummary() async -> SessionSummary? {
        guard let session = currentSession else { return nil }

        do {
            let summary = try await aiService.generateSessionSummary(
                feedbackLog: session.feedbackLog,
                mountMode: session.mountMode,
                duration: session.duration,
                referenceProfile: activeReference?.profile
            )
            currentSession?.summary = summary
            if let updatedSession = currentSession {
                sessionStorage.save(updatedSession)
            }
            return summary
        } catch {
            errorMessage = "生成训练总结失败: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Feedback Helpers

    private func addAIFeedback(_ text: String, type: FeedbackType = .aiCoaching) {
        feedbackHistory.append(CoachingFeedback(text: text, isFromAI: true))
        currentSession?.feedbackLog.append(FeedbackEntry(text: text, type: type))
    }

    private func addRiderFeedback(_ text: String) {
        feedbackHistory.append(CoachingFeedback(text: text, isFromAI: false))
        currentSession?.feedbackLog.append(FeedbackEntry(text: text, type: .riderQuestion))
    }

    private func addSystemFeedback(_ text: String) {
        feedbackHistory.append(CoachingFeedback(text: text, isFromAI: true))
        currentSession?.feedbackLog.append(FeedbackEntry(text: text, type: .systemEvent))
    }
}

// MARK: - Supporting Types

struct TimestampedFrame {
    let image: UIImage
    let timestamp: Date
}

enum NetworkStatus {
    case good
    case weak
    case offline
    case rateLimited
    case error
}
