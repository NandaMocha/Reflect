import SwiftUI
import PhotosUI
import UIKit
import AVFoundation
import OSLog

// MARK: - Data Loading & Saving Extension

extension ReflectionEditorView {
    func loadExistingData() {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [PERF] loadExistingData started", log: .default, type: .info)

        switch mode {
        case .create:
            if let learning = preselectedLearning {
                selectedLearning = learning
            } else if !learnings.isEmpty {
                // Auto-fill with last used learning, or first by sortOrder
                if let lastUsedId = UserDefaults.standard.lastUsedLearningId(),
                   let lastUsed = learnings.first(where: { $0.id == lastUsedId }) {
                    selectedLearning = lastUsed
                } else {
                    selectedLearning = learnings.first
                }
            }
            os_log("✅ [PERF] loadExistingData (create) took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        case .edit(let reflection):
            // Load text data
            let textStart = CFAbsoluteTimeGetCurrent()
            title = reflection.title
            content = reflection.plainTextContent
            selectedLearning = reflection.learning
            selectedDate = reflection.createdAt
            os_log("📝 [PERF] Text loading took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - textStart) * 1000)

            // Load images
            let imageStart = CFAbsoluteTimeGetCurrent()
            let imageCount = reflection.images.count
            images = reflection.images
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap { imageAttachment in
                    guard let imageData = imageAttachment.imageData,
                          let image = UIImage(data: imageData) else { return nil }
                    existingImageIds.insert(imageAttachment.id)
                    return ImageInput(
                        id: imageAttachment.id,
                        image: image,
                        caption: imageAttachment.caption
                    )
                }
            os_log("🖼️ [PERF] Loaded %d images in %.3fms", log: .default, type: .info, imageCount, (CFAbsoluteTimeGetCurrent() - imageStart) * 1000)

            // Load voice recordings
            let voiceStart = CFAbsoluteTimeGetCurrent()
            let voiceCount = reflection.voiceRecordings.count
            voiceRecordings = reflection.voiceRecordings
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap {
                    guard let data = $0.audioData else { return nil }
                    return VoiceRecordingInput(
                        id: UUID(),
                        existingId: $0.id,
                        audioData: data,
                        transcription: $0.transcription,
                        language: $0.language,
                        duration: $0.duration,
                        waveformSamples: $0.waveformSamples
                    )
                }
            os_log("🎤 [PERF] Loaded %d voice recordings in %.3fms", log: .default, type: .info, voiceCount, (CFAbsoluteTimeGetCurrent() - voiceStart) * 1000)

            // Load videos
            let videoStart = CFAbsoluteTimeGetCurrent()
            let videoCount = reflection.videos.count
            videos = reflection.videos
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap { videoAttachment in
                    let itemStart = CFAbsoluteTimeGetCurrent()
                    guard let videoData = videoAttachment.videoData,
                          let thumbnailData = videoAttachment.thumbnailData,
                          let thumbnail = UIImage(data: thumbnailData) else {
                        os_log("⚠️ [PERF] Video thumbnail loading failed for %@", log: .default, type: .error, videoAttachment.id.uuidString)
                        return nil
                    }
                    existingVideoIds.insert(videoAttachment.id)
                    let result = VideoInput(
                        id: videoAttachment.id,
                        videoData: videoData,
                        thumbnailImage: thumbnail,
                        duration: videoAttachment.duration,
                        caption: videoAttachment.caption
                    )
                    os_log("🎬 [PERF] Video %@ (size: %.2fMB) took %.3fms", log: .default, type: .info,
                           videoAttachment.id.uuidString,
                           Double(videoData.count) / (1024 * 1024),
                           (CFAbsoluteTimeGetCurrent() - itemStart) * 1000)
                    return result
                }
            os_log("🎬 [PERF] Loaded %d videos in %.3fms", log: .default, type: .info, videoCount, (CFAbsoluteTimeGetCurrent() - videoStart) * 1000)

            hasChanges = false
            os_log("✅ [PERF] loadExistingData (edit) TOTAL took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
        }
    }

    func loadImages(from items: [PhotosPickerItem]) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [PERF] loadImages started with %d items", log: .default, type: .info, items.count)

        for (index, item) in items.enumerated() {
            let itemStart = CFAbsoluteTimeGetCurrent()
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let input = ImageInput(image: image)
                await MainActor.run {
                    images.append(input)
                    hasChanges = true
                }
                os_log("📷 [PERF] Loaded image %d/%d in %.3fms", log: .default, type: .info, index + 1, items.count, (CFAbsoluteTimeGetCurrent() - itemStart) * 1000)
            }
        }

        await MainActor.run {
            selectedPhotoItems = []
        }
        os_log("✅ [PERF] loadImages TOTAL took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    func processCapturedImage(_ image: UIImage) {
        let input = ImageInput(image: image)
        images.append(input)
        hasChanges = true
        os_log("📷 [PERF] Captured image processed", log: .default, type: .info)
    }

    func processCapturedVideo(_ videoURL: URL) {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🎬 [PERF] processCapturedVideo started", log: .default, type: .info)

        // Load video data immediately from the temporary file
        guard let videoData = try? Data(contentsOf: videoURL) else {
            os_log("⚠️ [PERF] Failed to load video data", log: .default, type: .error)
            return
        }
        let loadDataTime = CFAbsoluteTimeGetCurrent() - startTime
        os_log("📦 [PERF] Video data loaded (%.2fMB) in %.3fms", log: .default, type: .info,
               Double(videoData.count) / (1024 * 1024), loadDataTime * 1000)

        // Generate thumbnail from video
        let thumbnailStart = CFAbsoluteTimeGetCurrent()
        let thumbnail = generateThumbnail(from: videoURL)
        let duration = getVideoDuration(from: videoURL)
        os_log("🖼️ [PERF] Thumbnail generation took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - thumbnailStart) * 1000)

        let input = VideoInput(
            videoData: videoData,
            thumbnailImage: thumbnail,
            duration: duration
        )
        videos.append(input)
        hasChanges = true

        os_log("✅ [PERF] Video processing TOTAL took %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    private func generateThumbnail(from url: URL) -> UIImage {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            os_log("⚠️ [PERF] Thumbnail generation failed: %@", log: .default, type: .error, error.localizedDescription)
            // Return a placeholder image if thumbnail generation fails
            return UIImage(systemName: "video") ?? UIImage()
        }
    }

    private func getVideoDuration(from url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }

    // MARK: - Notification Observers

    func setupNotificationObservers() {
        // No streak notifications needed
    }
}
