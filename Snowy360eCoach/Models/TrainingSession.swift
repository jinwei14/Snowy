import Foundation

// MARK: - Training Session

struct TrainingSession: Identifiable, Codable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var mountMode: CameraMountMode
    var skillLevel: SkillLevel
    var referenceVideoId: UUID?          // Active reference video during session
    var feedbackLog: [FeedbackEntry]     // All AI feedback during session
    var framesAnalyzed: Int
    var turnsDetected: Int
    var summary: SessionSummary?

    init(mountMode: CameraMountMode, skillLevel: SkillLevel, referenceVideoId: UUID? = nil) {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.mountMode = mountMode
        self.skillLevel = skillLevel
        self.referenceVideoId = referenceVideoId
        self.feedbackLog = []
        self.framesAnalyzed = 0
        self.turnsDetected = 0
        self.summary = nil
    }

    var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    mutating func end() {
        endTime = Date()
    }
}

// MARK: - Feedback Entry (persisted in session)

struct FeedbackEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let text: String
    let type: FeedbackType

    init(text: String, type: FeedbackType) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.type = type
    }
}

enum FeedbackType: String, Codable {
    case aiCoaching       // AI 实时教练反馈
    case aiComparison     // AI 参考视频对比反馈
    case riderQuestion    // 骑手提问
    case aiAnswer         // AI 回答骑手提问
    case systemEvent      // 系统事件（连接、断连等）
}

// MARK: - Session Summary (generated post-session by GPT-4o)

struct SessionSummary: Codable {
    let overallAssessment: String       // 整体评价
    let strengths: [String]             // 做得好的方面
    let areasForImprovement: [String]   // 需要改进的方面
    let comparisonSummary: String?      // 与参考视频的对比总结（如果有）
    let nextSessionFocus: [String]      // 下次训练重点建议
    let technicalScores: TechnicalScores?
}

struct TechnicalScores: Codable {
    let edgeTiming: Int?        // 入刃时机 (0-100)
    let angulation: Int?        // 折叠程度 (0-100)
    let edgeAngle: Int?         // 立刃角度 (0-100)
    let rotation: Int?          // 旋转质量 (0-100)
    let balance: Int?           // 平衡性 (0-100)
    let overall: Int?           // 综合评分 (0-100)
}

// MARK: - Session Storage

final class SessionStorage {
    private let sessionsKey = "snowy_training_sessions"

    func save(_ session: TrainingSession) {
        var sessions = loadAll()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    func loadAll() -> [TrainingSession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([TrainingSession].self, from: data) else {
            return []
        }
        return sessions.sorted { $0.startTime > $1.startTime }
    }

    func delete(_ sessionId: UUID) {
        var sessions = loadAll()
        sessions.removeAll { $0.id == sessionId }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}
