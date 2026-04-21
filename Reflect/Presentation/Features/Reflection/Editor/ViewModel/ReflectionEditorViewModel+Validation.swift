import Foundation

// MARK: - Validation

extension ReflectionEditorViewModel {
    /// Matches the view's gate: a reflection is valid when it has a learning selected
    /// and at least one of: non-empty content, images, videos, or voice recordings.
    /// (Title is optional — the view substitutes a date-based default when empty.)
    var isValid: Bool {
        let hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMedia = !images.isEmpty || !videos.isEmpty || !voiceRecordings.isEmpty
        return (hasContent || hasMedia) && selectedLearning != nil
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if title.count > Constants.Limits.reflectionTitleMaxLength {
            errors.append("Title is too long")
        }
        let hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMedia = !images.isEmpty || !videos.isEmpty || !voiceRecordings.isEmpty
        if !hasContent && !hasMedia {
            errors.append("Add text or media before saving")
        }
        if selectedLearning == nil {
            errors.append("Please select a learning")
        }
        if images.count > Constants.Limits.maxImagesPerReflection {
            errors.append("Too many images (max \(Constants.Limits.maxImagesPerReflection))")
        }
        if videos.count > Constants.Limits.maxVideosPerReflection {
            errors.append("Too many videos (max \(Constants.Limits.maxVideosPerReflection))")
        }
        if voiceRecordings.count > Constants.Limits.maxVoiceNotesPerReflection {
            errors.append("Too many voice recordings (max \(Constants.Limits.maxVoiceNotesPerReflection))")
        }
        return errors
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
}
