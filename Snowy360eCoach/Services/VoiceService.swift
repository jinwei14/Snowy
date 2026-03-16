import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Voice Service (TTS + STT)

@MainActor
final class VoiceService: NSObject, ObservableObject {
    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false

    // STT
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    @Published var isListening = false
    @Published var recognizedText = ""

    // Sentence buffer for streaming TTS
    private var sentenceBuffer = ""
    private let sentenceBoundaries: Set<Character> = ["。", "！", "？", "，", "；", "!", "?", ","]

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }

    // MARK: - TTS (Text-to-Speech)

    /// Speak a complete coaching message
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2  // Slightly faster for coaching
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// Feed streaming tokens from AI — speaks as soon as a sentence boundary is reached.
    /// This is the key latency optimization: start speaking before the full response arrives.
    func feedStreamingToken(_ token: String) {
        sentenceBuffer += token

        // Check for sentence boundaries
        if let lastChar = token.last, sentenceBoundaries.contains(lastChar) {
            let sentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                speak(sentence)
            }
            sentenceBuffer = ""
        }
    }

    /// Flush any remaining text in the buffer (call when streaming ends)
    func flushSpeechBuffer() {
        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            speak(remaining)
        }
        sentenceBuffer = ""
    }

    /// Stop all speech immediately
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        sentenceBuffer = ""
    }

    // MARK: - STT (Speech-to-Text) — Push-to-Talk

    /// Check and request speech recognition permission
    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Start listening for rider's voice (push-to-talk)
    func startListening() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }

        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw VoiceError.requestCreationFailed
        }

        // Use on-device recognition when available (lower latency, no network)
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.recognizedText = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopListeningInternal()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        recognizedText = ""
    }

    /// Stop listening and finalize recognition
    func stopListening() -> String {
        let text = recognizedText
        stopListeningInternal()
        return text
    }

    private func stopListeningInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Voice Errors

enum VoiceError: LocalizedError {
    case recognizerUnavailable
    case requestCreationFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "语音识别不可用"
        case .requestCreationFailed: return "无法创建语音识别请求"
        }
    }
}
