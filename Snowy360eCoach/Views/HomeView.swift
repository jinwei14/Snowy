import SwiftUI

// MARK: - Home View (Main Screen)

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sessionManager: TrainingSessionManager
    @EnvironmentObject var cameraService: CameraService

    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // App Title
                    VStack(spacing: 8) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("Snowy 360 eCoach")
                            .font(.largeTitle.bold())
                        Text("AI 单板滑雪教练")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)

                    Spacer()

                    // Camera connection status
                    connectionStatusCard

                    // Main actions
                    VStack(spacing: 16) {
                        // Connect / Start Training
                        if cameraService.connectionState == .connected {
                            NavigationLink {
                                MountModeSelectionView()
                            } label: {
                                actionButton(
                                    title: "开始训练",
                                    subtitle: "选择安装方式并开始",
                                    icon: "play.circle.fill",
                                    color: .green
                                )
                            }
                        } else {
                            Button {
                                cameraService.connect()
                            } label: {
                                actionButton(
                                    title: "连接相机",
                                    subtitle: "连接 Insta360 X5",
                                    icon: "wifi",
                                    color: .blue
                                )
                            }
                        }

                        // Reference Videos
                        NavigationLink {
                            ReferenceVideoListView()
                        } label: {
                            actionButton(
                                title: "参考视频",
                                subtitle: "管理对比视频库",
                                icon: "video.badge.plus",
                                color: .orange
                            )
                        }

                        // Training History
                        NavigationLink {
                            TrainingHistoryView()
                        } label: {
                            actionButton(
                                title: "训练记录",
                                subtitle: "查看历史训练与总结",
                                icon: "clock.arrow.circlepath",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Components

    private var connectionStatusCard: some View {
        HStack {
            Circle()
                .fill(connectionColor)
                .frame(width: 12, height: 12)
            Text(connectionText)
                .font(.subheadline)
            Spacer()
            if cameraService.connectionState == .connecting {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var connectionColor: Color {
        switch cameraService.connectionState {
        case .connected:    return .green
        case .connecting:   return .orange
        case .disconnected: return .gray
        case .error:        return .red
        }
    }

    private var connectionText: String {
        switch cameraService.connectionState {
        case .connected:       return "Insta360 X5 已连接"
        case .connecting:      return "正在连接..."
        case .disconnected:    return "相机未连接"
        case .error(let msg):  return "连接失败: \(msg)"
        }
    }

    private func actionButton(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(color)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
