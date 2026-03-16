import SwiftUI

// MARK: - Training Summary View (Post-Session)

struct TrainingSummaryView: View {
    @EnvironmentObject var sessionManager: TrainingSessionManager

    @State private var summary: SessionSummary?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        loadingView
                    } else if let summary {
                        summaryContent(summary)
                    } else {
                        errorView
                    }
                }
                .padding()
            }
            .navigationTitle("训练总结")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            summary = await sessionManager.generateSummary()
            isLoading = false
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("AI 正在生成训练分析报告...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("使用 GPT-4o 深度分析")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Summary Content

    private func summaryContent(_ summary: SessionSummary) -> some View {
        VStack(spacing: 20) {
            // Session info
            sessionInfoCard

            // Technical scores
            if let scores = summary.technicalScores {
                scoresCard(scores)
            }

            // Overall assessment
            sectionCard(title: "整体评价", icon: "star.fill", color: .blue) {
                Text(summary.overallAssessment)
                    .font(.body)
            }

            // Strengths
            sectionCard(title: "做得好的方面", icon: "hand.thumbsup.fill", color: .green) {
                ForEach(summary.strengths, id: \.self) { strength in
                    Label(strength, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }

            // Areas for improvement
            sectionCard(title: "需要改进", icon: "arrow.up.circle.fill", color: .orange) {
                ForEach(summary.areasForImprovement, id: \.self) { area in
                    Label(area, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }

            // Comparison summary
            if let comparison = summary.comparisonSummary {
                sectionCard(title: "参考视频对比", icon: "video.fill", color: .purple) {
                    Text(comparison)
                        .font(.subheadline)
                }
            }

            // Next session focus
            sectionCard(title: "下次训练重点", icon: "target", color: .red) {
                ForEach(summary.nextSessionFocus, id: \.self) { focus in
                    Label(focus, systemImage: "arrow.right.circle")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Session Info Card

    private var sessionInfoCard: some View {
        HStack(spacing: 24) {
            VStack {
                Text(sessionManager.currentSession?.durationFormatted ?? "--")
                    .font(.title2.bold())
                Text("训练时长")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack {
                Text("\(sessionManager.currentSession?.framesAnalyzed ?? 0)")
                    .font(.title2.bold())
                Text("分析帧数")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack {
                Text(sessionManager.mountMode.displayName)
                    .font(.title2.bold())
                Text("安装模式")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Scores Card

    private func scoresCard(_ scores: TechnicalScores) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("技术评分", systemImage: "chart.bar.fill")
                .font(.headline)

            if let overall = scores.overall {
                HStack {
                    Text("综合评分")
                        .font(.subheadline)
                    Spacer()
                    Text("\(overall)")
                        .font(.title.bold())
                        .foregroundColor(scoreColor(overall))
                    Text("/ 100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            scoreRow("入刃时机", score: scores.edgeTiming)
            scoreRow("折叠程度", score: scores.angulation)
            scoreRow("立刃角度", score: scores.edgeAngle)
            scoreRow("旋转质量", score: scores.rotation)
            scoreRow("平衡性", score: scores.balance)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func scoreRow(_ label: String, score: Int?) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            if let score {
                ProgressView(value: Double(score), total: 100)
                    .frame(width: 80)
                    .tint(scoreColor(score))
                Text("\(score)")
                    .font(.subheadline.bold())
                    .frame(width: 30, alignment: .trailing)
            } else {
                Text("--")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .yellow
        case 40..<60:  return .orange
        default:        return .red
        }
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("无法生成训练总结")
                .font(.headline)
            Text("请检查网络连接后重试")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("重试") {
                isLoading = true
                Task {
                    summary = await sessionManager.generateSummary()
                    isLoading = false
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 60)
    }
}
