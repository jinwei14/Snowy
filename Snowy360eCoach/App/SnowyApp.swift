import SwiftUI

// MARK: - App Entry Point

@main
struct SnowyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appState)
                .environmentObject(appState.sessionManager)
                .environmentObject(appState.cameraService)
                .environmentObject(appState.voiceService)
                .environmentObject(appState.referenceManager)
        }
    }
}

// MARK: - App State (shared dependency container)

@MainActor
final class AppState: ObservableObject {
    let cameraService: CameraService
    let aiService: AICoachingService
    let voiceService: VoiceService
    let motionService: MotionDetectionService
    let sessionManager: TrainingSessionManager
    let referenceManager: ReferenceVideoManager

    init() {
        let camera = CameraService(frameCaptureInterval: AppConfig.defaultFrameInterval)
        let ai = AICoachingService(githubToken: AppConfig.githubToken)
        let voice = VoiceService()
        let motion = MotionDetectionService()

        self.cameraService = camera
        self.aiService = ai
        self.voiceService = voice
        self.motionService = motion
        self.sessionManager = TrainingSessionManager(
            cameraService: camera,
            aiService: ai,
            voiceService: voice,
            motionService: motion
        )
        self.referenceManager = ReferenceVideoManager(aiService: ai)
    }
}
