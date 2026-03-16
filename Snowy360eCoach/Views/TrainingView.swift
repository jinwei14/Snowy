import SwiftUI

// MARK: - Training View (Main Training Screen)
// Shows live preview, coaching feedback, voice controls during active training.

struct TrainingView: View {
    @EnvironmentObject var sessionManager: TrainingSessionManager
    @EnvironmentObject var cameraService: CameraService
    @EnvironmentObject var voiceService: VoiceService

    @State private var showSummary = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Camera preview area
                cameraPreviewArea
                    .frame(maxHeight: .infinity, alignment: .top)

                // Coaching feedback overlay
                feedbackOverlay

                // Control bar
                controlBar
            }

            // Status indicators
            VStack {
                HStack {
                    statusBadges
                    Spacer()
                    timerBadge
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            sessionManager.startTraining()
        }
        .sheet(isPresented: $showSummary) {
            TrainingSummaryView()
        }
    }

    // MARK: - Camera Preview

    private var cameraPreviewArea: some View {
        ZStack {
            // Camera preview placeholder (in production: INSCameraSessionPlayer renderView)
            if let frame = cameraService.latestFrame {
                Image(uiImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.5))
                            Text("实时预览")
                                .foregroundColor(.white.opacity(0.5))
                        }
                    )
            }

            // Analysis indicator
            if sessionManager.isAnalyzing {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                            Text("AI 分析中")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(20)
                        .padding(8)
                    }
                }
            }
        }
        .clipped()
    }

    // MARK: - Coaching Feedback Overlay

    private var feedbackOverlay: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionManager.feedbackHistory.suffix(AppConfig.maxFeedbackDisplay)) { feedback in
                        FeedbackBubble(feedback: feedback)
                            .id(feedback.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(height: 200)
            .background(Color.black.opacity(0.7))
            .onChange(of: sessionManager.feedbackHistory.count) {
                if let lastId = sessionManager.feedbackHistory.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 32) {
            // Push-to-talk button
            Button {
                if voiceService.isListening {
                    sessionManager.stopListeningAndAsk()
                } else {
                    sessionManager.startListening()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: voiceService.isListening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundColor(voiceService.isListening ? .red : .white)
                    Text(voiceService.isListening ? "松开发送" : "按住说话")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Pause / Resume
            Button {
                if sessionManager.trainingState == .active {
                    sessionManager.pauseTraining()
                } else if sessionManager.trainingState == .paused {
                    sessionManager.resumeTraining()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: sessionManager.trainingState == .paused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                    Text(sessionManager.trainingState == .paused ? "继续" : "暂停")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // End training
            Button {
                sessionManager.endTraining()
                showSummary = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                    Text("结束训练")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.9))
    }

    // MARK: - Status Badges

    private var statusBadges: some View {
        HStack(spacing: 8) {
            // Network status
            StatusBadge(
                icon: networkIcon,
                color: networkColor
            )

            // Mount mode
            StatusBadge(
                icon: "camera",
                label: sessionManager.mountMode.displayName,
                color: .blue
            )

            // Reference video active
            if sessionManager.activeReference != nil {
                StatusBadge(
                    icon: "video.fill",
                    label: "对比",
                    color: .orange
                )
            }
        }
    }

    private var timerBadge: some View {
        Text(sessionManager.currentSession?.durationFormatted ?? "0:00")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
    }

    private var networkIcon: String {
        switch sessionManager.networkStatus {
        case .good:        return "wifi"
        case .weak:        return "wifi.exclamationmark"
        case .offline:     return "wifi.slash"
        case .rateLimited: return "exclamationmark.triangle"
        case .error:       return "xmark.circle"
        }
    }

    private var networkColor: Color {
        switch sessionManager.networkStatus {
        case .good:        return .green
        case .weak:        return .yellow
        case .offline:     return .red
        case .rateLimited: return .orange
        case .error:       return .red
        }
    }
}

// MARK: - Feedback Bubble

struct FeedbackBubble: View {
    let feedback: CoachingFeedback

    var body: some View {
        HStack {
            if feedback.isFromAI {
                aiBubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                riderBubble
            }
        }
    }

    private var aiBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "snowflake")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(12)

            Text(feedback.text)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(10)
                .background(Color.blue.opacity(0.6))
                .cornerRadius(12)
        }
    }

    private var riderBubble: some View {
        Text(feedback.text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(10)
            .background(Color.green.opacity(0.6))
            .cornerRadius(12)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let icon: String
    var label: String? = nil
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            if let label {
                Text(label)
                    .font(.caption2)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.7))
        .cornerRadius(8)
    }
}
