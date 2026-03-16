import SwiftUI
import PhotosUI

// MARK: - Reference Video List View

struct ReferenceVideoListView: View {
    @EnvironmentObject var referenceManager: ReferenceVideoManager

    @State private var showAddSheet = false

    var body: some View {
        List {
            if referenceManager.referenceVideos.isEmpty {
                emptyState
            } else {
                ForEach(referenceManager.referenceVideos) { video in
                    ReferenceVideoCell(video: video)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        referenceManager.deleteVideo(referenceManager.referenceVideos[index].id)
                    }
                }
            }
        }
        .navigationTitle("参考视频")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddReferenceVideoView()
        }
        .overlay {
            if referenceManager.isAnalyzing {
                analysisOverlay
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没有参考视频")
                .font(.headline)
            Text("上传高手的滑雪视频，AI 会分析技术要点\n训练时自动对比你和高手的差距")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var analysisOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text(referenceManager.analysisProgress)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(.systemGray2).opacity(0.9))
            .cornerRadius(20)
        }
    }
}

// MARK: - Reference Video Cell

struct ReferenceVideoCell: View {
    @EnvironmentObject var referenceManager: ReferenceVideoManager
    let video: ReferenceVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "video.fill")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.name)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(video.technique.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        Text(video.sourceAngle.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()

                if video.isAnalyzed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                } else {
                    Button("分析") {
                        Task {
                            await referenceManager.analyzeVideo(video.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if video.isAnalyzed, let profile = video.profile {
                Text(profile.overallDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Reference Video Sheet

struct AddReferenceVideoView: View {
    @EnvironmentObject var referenceManager: ReferenceVideoManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var technique: TechniqueCategory = .carving
    @State private var sourceAngle: VideoAngle = .handheld360
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?

    private let techniques: [TechniqueCategory] = [.carving, .figure8, .turns, .jumps, .rails]

    var body: some View {
        NavigationStack {
            Form {
                Section("视频信息") {
                    TextField("名称（例：八字刻滑 - 大神教学）", text: $name)

                    Picker("技术类型", selection: $technique) {
                        ForEach(techniques, id: \.id) { tech in
                            Text(tech.displayName).tag(tech)
                        }
                    }

                    Picker("拍摄角度", selection: $sourceAngle) {
                        ForEach(VideoAngle.allCases) { angle in
                            Text(angle.displayName).tag(angle)
                        }
                    }
                }

                Section("选择视频") {
                    PhotosPicker(
                        selection: $selectedVideoItem,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "film")
                            Text(selectedVideoURL != nil ? "已选择视频" : "从相册选择")
                        }
                    }
                    .onChange(of: selectedVideoItem) { _, newItem in
                        Task {
                            if let item = newItem,
                               let data = try? await item.loadTransferable(type: Data.self) {
                                // Save to temp file
                                let tempURL = FileManager.default.temporaryDirectory
                                    .appendingPathComponent(UUID().uuidString + ".mp4")
                                try? data.write(to: tempURL)
                                selectedVideoURL = tempURL
                            }
                        }
                    }
                }

                Section {
                    Text("上传后 AI 会使用 GPT-4o 深度分析视频中的技术要点，生成技术基准用于实时对比训练。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("添加参考视频")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        guard let url = selectedVideoURL, !name.isEmpty else { return }
                        referenceManager.addVideo(
                            name: name,
                            technique: technique,
                            videoURL: url,
                            sourceAngle: sourceAngle
                        )
                        dismiss()
                    }
                    .disabled(name.isEmpty || selectedVideoURL == nil)
                }
            }
        }
    }
}
