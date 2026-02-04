import Foundation
import SwiftData
import UIKit
import AVFoundation
import OSLog

// MARK: - Quick Actions Extension

extension ReflectionListViewModel {
    // MARK: - Types

    private struct ProcessedImageResult {
        let imageData: Data?
        let thumbnailData: Data?
    }

    // MARK: - Helper Methods

    /// Get the Learning to use for quick reflections
    /// - Returns: Last used Learning, or first available Learning, or nil if none exist
    func getLearningForQuickReflection(availableLearnings: [Learning]) -> Learning? {
        // Try last used first
        if let lastUsedId = UserDefaults.standard.lastUsedLearningId(),
           let lastUsed = availableLearnings.first(where: { $0.id == lastUsedId }) {
            return lastUsed
        }

        // Fall back to first Learning by sortOrder
        let sorted = availableLearnings.sorted { $0.sortOrder < $1.sortOrder }
        return sorted.first
    }

    /// Validate that a Learning can be used for quick reflection
    func validateLearningForQuickReflection(availableLearnings: [Learning]) -> (isValid: Bool, learning: Learning?, error: String?) {
        guard let learning = getLearningForQuickReflection(availableLearnings: availableLearnings) else {
            return (false, nil, "Please create a Learning first before adding reflections")
        }
        return (true, learning, nil)
    }

    // MARK: - Quick Reflection Creation

    /// Creates a quick reflection with an image attachment
    @MainActor
    func createQuickReflectionWithImage(
        learning: Learning,
        image: UIImage,
        availableLearnings: [Learning]
    ) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [QUICK] Creating quick reflection with image", log: .default, type: .info)

        isCreatingQuickReflection = true
        quickReflectionError = nil

        defer { isCreatingQuickReflection = false }

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: "" // Empty content for image-only reflection
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Process image
        let imageService = ImageProcessingService.shared
        let imageData = await imageService.compressImage(image, quality: .high)
        let thumbnailData = await imageService.generateThumbnail(image, size: CGSize(width: 200, height: 200))

        guard let compressedData = imageData, let thumbData = thumbnailData else {
            quickReflectionError = "Failed to process image"
            os_log("⚠️ [QUICK] Image processing failed", log: .default, type: .error)
            throw QuickReflectionError.imageProcessingFailed
        }

        let attachment = ImageAttachment(
            imageData: compressedData,
            thumbnailData: thumbData,
            caption: nil
        )
        attachment.sortOrder = 0
        reflection.images.append(attachment)

        // Save
        modelContext.insert(reflection)
        try modelContext.save()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        os_log("✅ [QUICK] Reflection created with image in %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    /// Creates a quick reflection with a video attachment
    @MainActor
    func createQuickReflectionWithVideo(
        learning: Learning,
        videoURL: URL,
        thumbnail: UIImage,
        duration: TimeInterval,
        availableLearnings: [Learning]
    ) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [QUICK] Creating quick reflection with video", log: .default, type: .info)

        isCreatingQuickReflection = true
        quickReflectionError = nil

        defer { isCreatingQuickReflection = false }

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: ""
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Load video data
        guard let videoData = try? Data(contentsOf: videoURL) else {
            quickReflectionError = "Failed to load video"
            os_log("⚠️ [QUICK] Video loading failed", log: .default, type: .error)
            throw QuickReflectionError.videoProcessingFailed
        }

        // Generate thumbnail as JPEG
        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
            quickReflectionError = "Failed to process thumbnail"
            throw QuickReflectionError.videoProcessingFailed
        }

        let attachment = VideoAttachment(
            videoData: videoData,
            thumbnailData: thumbnailData,
            caption: nil,
            duration: duration
        )
        attachment.sortOrder = 0
        reflection.videos.append(attachment)

        // Save
        modelContext.insert(reflection)
        try modelContext.save()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        os_log("✅ [QUICK] Reflection created with video in %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    /// Creates a quick reflection with a voice recording
    @MainActor
    func createQuickReflectionWithVoice(
        learning: Learning,
        recording: VoiceRecordingInput,
        availableLearnings: [Learning]
    ) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        os_log("🚀 [QUICK] Creating quick reflection with voice", log: .default, type: .info)

        isCreatingQuickReflection = true
        quickReflectionError = nil

        defer { isCreatingQuickReflection = false }

        // Use transcription as content, or default text
        let content = recording.transcription ?? "Voice note"

        // Generate default title
        let title = generateDefaultTitle()

        // Create reflection
        let reflection = Reflection(
            title: title,
            plainTextContent: content
        )
        reflection.learning = learning
        reflection.createdAt = Date()

        // Create voice recording attachment
        let voiceRecording = VoiceRecording(
            audioData: recording.audioData,
            transcription: recording.transcription,
            language: recording.language,
            duration: recording.duration
        )
        voiceRecording.sortOrder = 0
        reflection.voiceRecordings.append(voiceRecording)

        // Save
        modelContext.insert(reflection)
        try modelContext.save()

        // Track last used learning
        UserDefaults.standard.setLastUsedLearningId(learning.id)

        os_log("✅ [QUICK] Reflection created with voice in %.3fms", log: .default, type: .info, (CFAbsoluteTimeGetCurrent() - startTime) * 1000)
    }

    // MARK: - Private Helpers

    private func generateDefaultTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d"
        return "Reflection on \(formatter.string(from: Date()))"
    }
}

// MARK: - Errors

enum QuickReflectionError: LocalizedError {
    case noLearningAvailable
    case imageProcessingFailed
    case videoProcessingFailed
    case voiceProcessingFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noLearningAvailable:
            return "Please create a Learning first before adding reflections"
        case .imageProcessingFailed:
            return "Failed to process the image"
        case .videoProcessingFailed:
            return "Failed to process the video"
        case .voiceProcessingFailed:
            return "Failed to process the voice recording"
        case .saveFailed:
            return "Failed to save the reflection"
        }
    }
}
