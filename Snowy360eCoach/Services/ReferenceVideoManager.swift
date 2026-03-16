import Foundation
import UIKit
import AVFoundation

// MARK: - Reference Video Manager
// Handles uploading, storing, and AI pre-analysis of reference videos.

@MainActor
final class ReferenceVideoManager: ObservableObject {
    @Published var referenceVideos: [ReferenceVideo] = []
    @Published var isAnalyzing = false
    @Published var analysisProgress: String = ""

    private let aiService: AICoachingService
    private let storageKey = "snowy_reference_videos"

    init(aiService: AICoachingService) {
        self.aiService = aiService
        loadVideos()
    }

    // MARK: - Add Reference Video

    func addVideo(name: String, technique: TechniqueCategory, videoURL: URL, sourceAngle: VideoAngle) {
        // Copy video to app's documents directory
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsURL.appendingPathComponent("references/\(UUID().uuidString).mp4")

        do {
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: videoURL, to: destURL)

            let video = ReferenceVideo(
                name: name,
                technique: technique,
                videoURL: destURL,
                sourceAngle: sourceAngle
            )
            referenceVideos.append(video)
            saveVideos()
        } catch {
            print("Failed to copy reference video: \(error)")
        }
    }

    // MARK: - AI Pre-Analysis

    /// Extract key frames from video and send to GPT-4o for deep analysis
    func analyzeVideo(_ videoId: UUID) async {
        guard let index = referenceVideos.firstIndex(where: { $0.id == videoId }) else { return }

        isAnalyzing = true
        analysisProgress = "提取关键帧..."

        do {
            // Extract key frames from the video
            let keyFrames = try await extractKeyFrames(from: referenceVideos[index].videoURL)
            analysisProgress = "AI 分析中... (使用 GPT-4o)"

            // Send key frames to GPT-4o for analysis
            let framesForAPI = keyFrames.map { (image: $0.image, timestamp: $0.timestamp) }
            let profile = try await aiService.analyzeReferenceVideo(
                keyFrames: framesForAPI,
                technique: referenceVideos[index].technique
            )

            // Update the reference video with analysis results
            referenceVideos[index].profile = profile
            referenceVideos[index].keyFrames = keyFrames.enumerated().map { idx, frame in
                ReferenceKeyFrame(
                    timestamp: frame.timestamp,
                    phase: TurnPhase.allCases[idx % TurnPhase.allCases.count],
                    imageData: frame.image.jpegData(compressionQuality: 0.8),
                    analysis: profile.keyPoints[safe: idx] ?? ""
                )
            }
            referenceVideos[index].isAnalyzed = true
            saveVideos()

            analysisProgress = "分析完成！"
        } catch {
            analysisProgress = "分析失败: \(error.localizedDescription)"
        }

        isAnalyzing = false
    }

    // MARK: - Key Frame Extraction

    private struct ExtractedFrame {
        let image: UIImage
        let timestamp: TimeInterval
    }

    private func extractKeyFrames(from videoURL: URL, count: Int = 5) async throws -> [ExtractedFrame] {
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 512)  // Reasonable size for analysis

        var frames: [ExtractedFrame] = []
        let interval = durationSeconds / Double(count + 1)

        for i in 1...count {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                let image = UIImage(cgImage: cgImage)
                frames.append(ExtractedFrame(image: image, timestamp: interval * Double(i)))
            } catch {
                continue  // Skip frames that fail to extract
            }
        }

        return frames
    }

    // MARK: - Delete

    func deleteVideo(_ videoId: UUID) {
        guard let index = referenceVideos.firstIndex(where: { $0.id == videoId }) else { return }
        let video = referenceVideos[index]

        // Delete the video file
        try? FileManager.default.removeItem(at: video.videoURL)

        referenceVideos.remove(at: index)
        saveVideos()
    }

    // MARK: - Persistence

    private func saveVideos() {
        if let data = try? JSONEncoder().encode(referenceVideos) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadVideos() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let videos = try? JSONDecoder().decode([ReferenceVideo].self, from: data) else {
            return
        }
        referenceVideos = videos
    }
}

// MARK: - Collection Safe Subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
