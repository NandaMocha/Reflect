import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

// MARK: - Data Loading & Saving Extension

extension ReflectionEditorView {
    func loadExistingData() {
        switch mode {
        case .create:
            if let learning = preselectedLearning {
                selectedLearning = learning
            }
        case .edit(let reflection):
            title = reflection.title
            content = reflection.plainTextContent
            selectedLearning = reflection.learning
            selectedDate = reflection.createdAt

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
                        duration: $0.duration
                    )
                }

            videos = reflection.videos
                .sorted(by: { $0.sortOrder < $1.sortOrder })
                .compactMap { videoAttachment in
                    guard let thumbnailData = videoAttachment.thumbnailData,
                          let thumbnail = UIImage(data: thumbnailData) else { return nil }
                    existingVideoIds.insert(videoAttachment.id)
                    return VideoInput(
                        id: videoAttachment.id,
                        videoURL: URL(fileURLWithPath: ""), // Placeholder, actual data is in videoData
                        thumbnailImage: thumbnail,
                        duration: videoAttachment.duration,
                        caption: videoAttachment.caption
                    )
                }

            hasChanges = false
        }
    }

    func loadImages(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let input = ImageInput(image: image)
                await MainActor.run {
                    images.append(input)
                    hasChanges = true
                }
            }
        }
        await MainActor.run {
            selectedPhotoItems = []
        }
    }

    func processCapturedImage(_ image: UIImage) {
        let input = ImageInput(image: image)
        images.append(input)
        hasChanges = true
    }

    func processCapturedVideo(_ videoURL: URL) {
        // Generate thumbnail from video
        let thumbnail = generateThumbnail(from: videoURL)
        let duration = getVideoDuration(from: videoURL)

        let input = VideoInput(
            videoURL: videoURL,
            thumbnailImage: thumbnail,
            duration: duration
        )
        videos.append(input)
        hasChanges = true
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
            // Return a placeholder image if thumbnail generation fails
            return UIImage(systemName: "video") ?? UIImage()
        }
    }

    private func getVideoDuration(from url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}
