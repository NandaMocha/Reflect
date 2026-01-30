import Foundation

// MARK: - Validation

extension ReflectionEditorViewModel {
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !content.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedLearning != nil
    }

    var validationErrors: [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Title is required")
        }
        if title.count > Constants.Limits.reflectionTitleMaxLength {
            errors.append("Title is too long")
        }
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Content is required")
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
