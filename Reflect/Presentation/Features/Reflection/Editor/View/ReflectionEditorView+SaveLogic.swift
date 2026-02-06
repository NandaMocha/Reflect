import SwiftUI
import SwiftData
import Foundation

// MARK: - Save Logic Extension

extension ReflectionEditorView {
    // MARK: - Types for Concurrent Image Processing

    private struct ProcessedImageResult {
        let index: Int
        let imageData: Data?
        let thumbnailData: Data?
        let caption: String?
    }

    private struct ProcessedVideoResult {
        let index: Int
        let videoData: Data?
        let thumbnailData: Data?
        let duration: TimeInterval
        let caption: String?
    }

    @MainActor
    func save() async {
        guard isValid else { return }
        isSaving = true

        do {
            switch mode {
            case .create:
                try await createReflection()
            case .edit(let reflection):
                try await updateReflection(reflection)
            }

            // Track last used learning when saving
            if let learning = selectedLearning {
                UserDefaults.standard.setLastUsedLearningId(learning.id)
            }

            HapticManager.shared.success()

            // Post notification to refresh reflection list
            NotificationCenter.default.post(name: .init("ReflectionDidSave"), object: nil)

            onDismiss?()
            dismiss()
        } catch {
            os_log("⚠️ [EDITOR] Failed to save: %@", log: .default, type: .error, error.localizedDescription)
            errorMessage = "Failed to save reflection: \(error.localizedDescription)"
            showErrorAlert = true
            HapticManager.shared.error()
        }

        isSaving = false
    }

    func createReflection() async throws {
        // Use default title if empty
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title.trimmingCharacters(in: .whitespaces)

        let reflection = Reflection(
            title: finalTitle,
            plainTextContent: content.trimmingCharacters(in: .whitespaces)
        )
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate

        // Save captured location from journaling suggestion
        if let location = capturedLocation {
            reflection.locationLatitude = location.latitude
            reflection.locationLongitude = location.longitude
            reflection.locationName = location.name
        }

        // Process images concurrently for better performance
        let imageResults = await processImagesConcurrently(images)

        for result in imageResults {
            if let imageData = result.imageData, let thumbnailData = result.thumbnailData {
                let attachment = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: result.caption
                )
                attachment.sortOrder = result.index
                reflection.images.append(attachment)
            }
        }

        for (index, voiceInput) in voiceRecordings.enumerated() {
            let recording = VoiceRecording(
                audioData: voiceInput.audioData,
                transcription: voiceInput.transcription,
                language: voiceInput.language,
                duration: voiceInput.duration
            )
            recording.sortOrder = index
            reflection.voiceRecordings.append(recording)
        }

        // Process videos
        let videoResults = await processVideosConcurrently(videos)

        for result in videoResults {
            if let videoData = result.videoData, let thumbnailData = result.thumbnailData {
                let attachment = VideoAttachment(
                    videoData: videoData,
                    thumbnailData: thumbnailData,
                    caption: result.caption,
                    duration: result.duration
                )
                attachment.sortOrder = result.index
                reflection.videos.append(attachment)
            }
        }

        modelContext.insert(reflection)
        try modelContext.save()
    }

    func updateReflection(_ reflection: Reflection) async throws {
        // Use default title if empty
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title.trimmingCharacters(in: .whitespaces)

        reflection.title = finalTitle
        reflection.plainTextContent = content.trimmingCharacters(in: .whitespaces)
        reflection.learning = selectedLearning
        reflection.createdAt = selectedDate
        reflection.updatedAt = Date()

        // Update location from journaling suggestion
        if let location = capturedLocation {
            reflection.locationLatitude = location.latitude
            reflection.locationLongitude = location.longitude
            reflection.locationName = location.name
        } else {
            // Clear location if removed (optional)
            reflection.locationLatitude = nil
            reflection.locationLongitude = nil
            reflection.locationName = nil
        }

        let currentImageIds = Set(images.map { $0.id })

        let imagesToRemove = reflection.images.filter { !currentImageIds.contains($0.id) }
        for image in imagesToRemove {
            modelContext.delete(image)
            if let index = reflection.images.firstIndex(where: { $0.id == image.id }) {
                reflection.images.remove(at: index)
            }
        }

        // Collect new images that need processing
        let newImages = images.filter { !existingImageIds.contains($0.id) }

        // Process new images concurrently
        let imageResults = await processImagesConcurrently(newImages)

        for result in imageResults {
            if let imageData = result.imageData, let thumbnailData = result.thumbnailData {
                let newImage = ImageAttachment(
                    imageData: imageData,
                    thumbnailData: thumbnailData,
                    caption: result.caption
                )
                newImage.sortOrder = result.index
                reflection.images.append(newImage)
            }
        }

        // Update existing images (no processing needed)
        for (index, imageInput) in images.enumerated() {
            if existingImageIds.contains(imageInput.id),
               let existingImage = reflection.images.first(where: { $0.id == imageInput.id }) {
                existingImage.sortOrder = index
                existingImage.caption = imageInput.caption
            }
        }

        let existingIdsToKeep = Set(voiceRecordings.compactMap { $0.existingId })

        let recordingsToRemove = reflection.voiceRecordings.filter { !existingIdsToKeep.contains($0.id) }
        for recording in recordingsToRemove {
            modelContext.delete(recording)
            if let index = reflection.voiceRecordings.firstIndex(where: { $0.id == recording.id }) {
                reflection.voiceRecordings.remove(at: index)
            }
        }

        for (index, input) in voiceRecordings.enumerated() {
            if let existingId = input.existingId,
               let existingRecording = reflection.voiceRecordings.first(where: { $0.id == existingId }) {
                existingRecording.sortOrder = index
            } else {
                let newRecording = VoiceRecording(
                    audioData: input.audioData,
                    transcription: input.transcription,
                    language: input.language,
                    duration: input.duration
                )
                newRecording.sortOrder = index
                reflection.voiceRecordings.append(newRecording)
            }
        }

        // Handle videos
        let currentVideoIds = Set(videos.map { $0.id })

        let videosToRemove = reflection.videos.filter { !currentVideoIds.contains($0.id) }
        for video in videosToRemove {
            modelContext.delete(video)
            if let index = reflection.videos.firstIndex(where: { $0.id == video.id }) {
                reflection.videos.remove(at: index)
            }
        }

        // Collect new videos that need processing
        let newVideos = videos.filter { !existingVideoIds.contains($0.id) }

        // Process new videos concurrently
        let videoResults = await processVideosConcurrently(newVideos)

        for result in videoResults {
            if let videoData = result.videoData, let thumbnailData = result.thumbnailData {
                let newVideo = VideoAttachment(
                    videoData: videoData,
                    thumbnailData: thumbnailData,
                    caption: result.caption,
                    duration: result.duration
                )
                newVideo.sortOrder = result.index
                reflection.videos.append(newVideo)
            }
        }

        // Update existing videos (no processing needed)
        for (index, videoInput) in videos.enumerated() {
            if existingVideoIds.contains(videoInput.id),
               let existingVideo = reflection.videos.first(where: { $0.id == videoInput.id }) {
                existingVideo.sortOrder = index
                existingVideo.caption = videoInput.caption
            }
        }

        try modelContext.save()
    }

    // MARK: - Concurrent Image Processing

    private func processImagesConcurrently(_ images: [ImageInput]) async -> [ProcessedImageResult] {
        let imageService = ImageProcessingService.shared

        // Process images concurrently using TaskGroup
        return await withTaskGroup(of: ProcessedImageResult.self) { group in
            for (index, imageInput) in images.enumerated() {
                group.addTask {
                    let imageData = await imageService.compressImage(imageInput.image, quality: CompressionQuality.high)
                    let thumbnailData = await imageService.generateThumbnail(imageInput.image, size: CGSize(width: 200, height: 200))

                    return ProcessedImageResult(
                        index: index,
                        imageData: imageData,
                        thumbnailData: thumbnailData,
                        caption: imageInput.caption
                    )
                }
            }

            var results: [ProcessedImageResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }
        }
    }

    // MARK: - Concurrent Video Processing

    private func processVideosConcurrently(_ videos: [VideoInput]) async -> [ProcessedVideoResult] {
        // Since video data is already loaded in VideoInput, just process thumbnail
        return await withTaskGroup(of: ProcessedVideoResult.self) { group in
            for (index, videoInput) in videos.enumerated() {
                group.addTask {
                    // Video data is already in memory, just need thumbnail as JPEG
                    let thumbnailData = videoInput.thumbnailImage.jpegData(compressionQuality: 0.8)

                    return ProcessedVideoResult(
                        index: index,
                        videoData: videoInput.videoData,
                        thumbnailData: thumbnailData,
                        duration: videoInput.duration,
                        caption: videoInput.caption
                    )
                }
            }

            var results: [ProcessedVideoResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.index < $1.index }
        }
    }
}
