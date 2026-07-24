import Foundation

// MARK: - Validation

extension ReflectionEditorViewModel {
    /// A reflection is valid when it has at least one of a non-empty title, non-empty
    /// content, images, videos, or voice recordings. The learning assignment is guaranteed
    /// by the caller — the editor is always opened from a specific learning's list — so it's
    /// not part of the gate here. `selectedLearning == nil` is still checked as a last-mile
    /// safety net because the use case requires a learningId.
    var isValid: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMedia = !images.isEmpty || !videos.isEmpty || !voiceRecordings.isEmpty
        return (hasTitle || hasContent || hasMedia) && selectedLearning != nil
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if title.count > Constants.Limits.reflectionTitleMaxLength {
            errors.append("Title is too long")
        }
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        let hasContent = !content.trimmingCharacters(in: .whitespaces).isEmpty
        let hasMedia = !images.isEmpty || !videos.isEmpty || !voiceRecordings.isEmpty
        if !hasTitle && !hasContent && !hasMedia {
            errors.append("Add a title, description, or media before saving")
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
