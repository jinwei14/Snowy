import SwiftUI

// MARK: - Mount Mode Selection View
// User selects how the camera is mounted before starting training.

struct MountModeSelectionView: View {
    @EnvironmentObject var sessionManager: TrainingSessionManager
    @EnvironmentObject var referenceManager: ReferenceVideoManager

    @State private var selectedMode: CameraMountMode = .handheld
    @State private var selectedReference: ReferenceVideo?
    @State private var navigateToTraining = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("选择安装方式")
                        .font(.title2.bold())
                    Text("AI 会根据安装方式调整分析策略")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Mount mode cards
                ForEach(CameraMountMode.allCases) { mode in
                    MountModeCard(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        onSelect: { selectedMode = mode }
                    )
                }

                // Safety warning for handheld
                if selectedMode == .handheld {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("手持模式需要单手滑行能力，建议中级以上水平使用")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }

                Divider()

                // Reference video selection (optional)
                VStack(alignment: .leading, spacing: 12) {
                    Text("参考视频对比（可选）")
                        .font(.headline)

                    let compatibleVideos = referenceManager.referenceVideos.filter {
                        $0.isAnalyzed && canUseForRealtimeComparison(reference: $0, currentMount: selectedMode)
                    }

                    if compatibleVideos.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text("暂无匹配当前安装方式的参考视频")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(compatibleVideos) { video in
                            ReferenceVideoRow(
                                video: video,
                                isSelected: selectedReference?.id == video.id,
                                onSelect: {
                                    selectedReference = selectedReference?.id == video.id ? nil : video
                                }
                            )
                        }
                    }
                }

                Divider()

                // Start button
                Button {
                    sessionManager.mountMode = selectedMode
                    sessionManager.activeReference = selectedReference
                    navigateToTraining = true
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("开始训练")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
            }
            .padding()
        }
        .navigationTitle("训练设置")
        .navigationDestination(isPresented: $navigateToTraining) {
            TrainingView()
        }
    }
}

// MARK: - Mount Mode Card

struct MountModeCard: View {
    let mode: CameraMountMode
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: modeIcon)
                    .font(.title)
                    .frame(width: 50, height: 50)
                    .foregroundColor(isSelected ? .white : .blue)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(analysisQuality)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.05) : Color(.systemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }

    private var modeIcon: String {
        switch mode {
        case .helmet:      return "shield.checkered"
        case .handheld:    return "hand.raised"
        case .thirdPerson: return "person.2"
        }
    }

    private var analysisQuality: String {
        switch mode {
        case .helmet:      return "AI分析精度: 中等"
        case .handheld:    return "AI分析精度: 高"
        case .thirdPerson: return "AI分析精度: 最高"
        }
    }
}

// MARK: - Reference Video Row

struct ReferenceVideoRow: View {
    let video: ReferenceVideo
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(video.technique.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.orange)
                }
            }
            .padding(12)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}
