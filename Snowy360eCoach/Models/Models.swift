import Foundation
import UIKit

// MARK: - Camera Mount Mode

enum CameraMountMode: String, CaseIterable, Identifiable, Codable {
    case helmet       // 头盔安装
    case handheld     // 手持自拍杆
    case thirdPerson  // 第三人称拍摄

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .helmet:      return "头盔安装"
        case .handheld:    return "手持自拍杆"
        case .thirdPerson: return "第三人称拍摄"
        }
    }

    var icon: String {
        switch self {
        case .helmet:      return "helmet"
        case .handheld:    return "hand.raised"
        case .thirdPerson: return "person.2"
        }
    }

    var description: String {
        switch self {
        case .helmet:
            return "双手自由，适合日常练习和高速滑行"
        case .handheld:
            return "全身可见，AI分析最准确（需单手滑行能力）"
        case .thirdPerson:
            return "朋友帮拍，外部视角最佳"
        }
    }
}

// MARK: - Video Angle (for reference videos)

enum VideoAngle: String, CaseIterable, Identifiable, Codable {
    case handheld360   // 手持 360°（自拍杆）
    case helmet360     // 头盔 360°
    case thirdPerson   // 第三人称（别人拍）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .handheld360: return "手持自拍杆 360°"
        case .helmet360:   return "头盔安装 360°"
        case .thirdPerson: return "第三人称拍摄"
        }
    }
}

// MARK: - Technique Category

enum TechniqueCategory: Codable, Hashable, Identifiable {
    case carving        // 刻滑
    case figure8        // 八字刻滑
    case turns          // 连续弯
    case jumps          // 跳跃
    case rails          // 道具
    case custom(String)

    var id: String {
        switch self {
        case .carving:         return "carving"
        case .figure8:         return "figure8"
        case .turns:           return "turns"
        case .jumps:           return "jumps"
        case .rails:           return "rails"
        case .custom(let name): return "custom_\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .carving:         return "刻滑"
        case .figure8:         return "八字刻滑"
        case .turns:           return "连续弯"
        case .jumps:           return "跳跃"
        case .rails:           return "道具"
        case .custom(let name): return name
        }
    }
}

// MARK: - Turn Phase

enum TurnPhase: String, CaseIterable, Codable {
    case preTurn         // 入弯前
    case edgeEngagement  // 入刃瞬间
    case midTurn         // 弯中
    case exitTurn        // 出弯

    var displayName: String {
        switch self {
        case .preTurn:        return "入弯前"
        case .edgeEngagement: return "入刃瞬间"
        case .midTurn:        return "弯中"
        case .exitTurn:       return "出弯"
        }
    }
}

// MARK: - Skill Level

enum SkillLevel: String, CaseIterable, Identifiable, Codable {
    case beginner     // 初学者
    case intermediate // 中级
    case advanced     // 高级

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner:     return "初学者"
        case .intermediate: return "中级"
        case .advanced:     return "高级"
        }
    }
}

// MARK: - Reference Video Models

struct ReferenceVideo: Identifiable, Codable {
    let id: UUID
    var name: String                     // "八字刻滑 - 大神教学"
    var technique: TechniqueCategory
    var videoURL: URL                    // 本地存储
    var keyFrames: [ReferenceKeyFrame]   // AI 预分析提取的关键帧
    var profile: ReferenceProfile?       // AI 生成的技术参数基准
    var sourceAngle: VideoAngle
    var createdAt: Date
    var isAnalyzed: Bool                 // 是否已完成 AI 预分析

    init(name: String, technique: TechniqueCategory, videoURL: URL, sourceAngle: VideoAngle) {
        self.id = UUID()
        self.name = name
        self.technique = technique
        self.videoURL = videoURL
        self.keyFrames = []
        self.profile = nil
        self.sourceAngle = sourceAngle
        self.createdAt = Date()
        self.isAnalyzed = false
    }
}

struct ReferenceKeyFrame: Identifiable, Codable {
    let id: UUID
    let timestamp: TimeInterval
    let phase: TurnPhase
    let imageData: Data?               // JPEG data of the key frame
    let analysis: String               // AI 对这一帧的技术描述

    init(timestamp: TimeInterval, phase: TurnPhase, imageData: Data?, analysis: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.phase = phase
        self.imageData = imageData
        self.analysis = analysis
    }
}

struct ReferenceProfile: Codable {
    let edgeTimingDescription: String    // 入刃时机描述
    let angulationLevel: String          // 折叠程度
    let edgeAngleDescription: String     // 立刃角度
    let rotationDescription: String      // 旋转幅度
    let overallDescription: String       // 整体技术总结
    let keyPoints: [String]              // 核心技术要点列表

    /// Serialized format for injection into the system prompt
    var promptDescription: String {
        """
        入刃时机: \(edgeTimingDescription)
        折叠程度: \(angulationLevel)
        立刃角度: \(edgeAngleDescription)
        旋转幅度: \(rotationDescription)
        整体评价: \(overallDescription)
        核心要点:
        \(keyPoints.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        """
    }
}

// MARK: - Angle Matching

/// V1: Only allow real-time comparison when angles match
func canUseForRealtimeComparison(reference: ReferenceVideo, currentMount: CameraMountMode) -> Bool {
    switch (currentMount, reference.sourceAngle) {
    case (.handheld, .handheld360):   return true
    case (.helmet, .helmet360):       return true
    case (.thirdPerson, .thirdPerson): return true
    default:                           return false
    }
}

// MARK: - Coaching Feedback

struct CoachingFeedback: Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let isFromAI: Bool       // true = AI coaching, false = rider question

    init(text: String, isFromAI: Bool) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.isFromAI = isFromAI
    }
}

// MARK: - Camera Connection State

enum CameraConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Training State

enum TrainingState: Equatable {
    case idle
    case preparing        // Connected, choosing mount mode
    case active           // Training in progress
    case paused
    case completed
}
