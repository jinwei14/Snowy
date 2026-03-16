import SwiftUI

// MARK: - Training History View

struct TrainingHistoryView: View {
    @State private var sessions: [TrainingSession] = []
    private let storage = SessionStorage()

    var body: some View {
        List {
            if sessions.isEmpty {
                emptyState
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        TrainingDetailView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        storage.delete(sessions[index].id)
                    }
                    sessions.remove(atOffsets: indexSet)
                }
            }
        }
        .navigationTitle("训练记录")
        .onAppear {
            sessions = storage.loadAll()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没有训练记录")
                .font(.headline)
            Text("完成一次训练后，记录和AI分析报告会显示在这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: TrainingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startTime, style: .date)
                    .font(.headline)
                Spacer()
                Text(session.durationFormatted)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Label(session.mountMode.displayName, systemImage: "camera")
                    .font(.caption)
                    .foregroundColor(.blue)

                Label("\(session.framesAnalyzed) 帧", systemImage: "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if session.summary != nil {
                    Label("已分析", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if let overall = session.summary?.technicalScores?.overall {
                HStack {
                    Text("综合评分")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(overall), total: 100)
                        .frame(width: 60)
                    Text("\(overall)/100")
                        .font(.caption.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Training Detail View

struct TrainingDetailView: View {
    let session: TrainingSession

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Session info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(session.mountMode.displayName, systemImage: "camera")
                        Spacer()
                        Text(session.startTime, style: .date)
                    }
                    HStack {
                        Label(session.durationFormatted, systemImage: "clock")
                        Spacer()
                        Label("\(session.framesAnalyzed) 帧分析", systemImage: "photo")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Summary
                if let summary = session.summary {
                    summarySection(summary)
                }

                // Feedback log
                VStack(alignment: .leading, spacing: 8) {
                    Text("训练反馈记录")
                        .font(.headline)

                    ForEach(session.feedbackLog) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(feedbackColor(entry.type))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .font(.subheadline)
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("训练详情")
    }

    private func summarySection(_ summary: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 分析报告")
                .font(.headline)

            Text(summary.overallAssessment)
                .font(.body)

            if !summary.strengths.isEmpty {
                Text("优点")
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
                ForEach(summary.strengths, id: \.self) { s in
                    Text("• \(s)").font(.subheadline)
                }
            }

            if !summary.areasForImprovement.isEmpty {
                Text("改进")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                ForEach(summary.areasForImprovement, id: \.self) { a in
                    Text("• \(a)").font(.subheadline)
                }
            }

            if !summary.nextSessionFocus.isEmpty {
                Text("下次重点")
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
                ForEach(summary.nextSessionFocus, id: \.self) { f in
                    Text("• \(f)").font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func feedbackColor(_ type: FeedbackType) -> Color {
        switch type {
        case .aiCoaching:   return .blue
        case .aiComparison: return .purple
        case .riderQuestion: return .green
        case .aiAnswer:     return .cyan
        case .systemEvent:  return .gray
        }
    }
}
