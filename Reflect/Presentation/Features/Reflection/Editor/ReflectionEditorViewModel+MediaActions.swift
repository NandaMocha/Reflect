import SwiftUI
import PhotosUI

// MARK: - Image Actions

extension ReflectionEditorViewModel {
    @MainActor
    func processSelectedPhotos() async {
        for item in selectedPhotoItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addImage(image)
            }
        }
        selectedPhotoItems = []
    }

    func addImage(_ image: UIImage) {
        guard images.count < Constants.Limits.maxImagesPerReflection else {
            errorMessage = "Maximum \(Constants.Limits.maxImagesPerReflection) images allowed"
            return
        }

        let input = ImageInput(image: image)
        images.append(input)
        hasChanges = true
        HapticManager.shared.success()
    }

    func removeImage(at index: Int) {
        guard index < images.count else { return }
        images.remove(at: index)
        hasChanges = true
        HapticManager.shared.lightImpact()
    }

    func updateImageCaption(at index: Int, caption: String) {
        guard index < images.count else { return }
        images[index].caption = caption
        hasChanges = true
    }
}

// MARK: - Video Actions

extension ReflectionEditorViewModel {
    func addVideo(_ video: VideoInput) {
        guard videos.count < Constants.Limits.maxVideosPerReflection else {
            errorMessage = "Maximum \(Constants.Limits.maxVideosPerReflection) videos allowed"
            return
        }

        videos.append(video)
        hasChanges = true
        HapticManager.shared.success()
    }

    func removeVideo(at index: Int) {
        guard index < videos.count else { return }
        videos.remove(at: index)
        hasChanges = true
        HapticManager.shared.lightImpact()
    }

    func updateVideoCaption(at index: Int, caption: String) {
        guard index < videos.count else { return }
        videos[index].caption = caption
        hasChanges = true
    }
}

// MARK: - Voice Recording Actions

extension ReflectionEditorViewModel {
    func addVoiceRecording(_ recording: VoiceRecordingInput) {
        guard voiceRecordings.count < Constants.Limits.maxVoiceNotesPerReflection else {
            errorMessage = "Maximum \(Constants.Limits.maxVoiceNotesPerReflection) voice recordings allowed"
            return
        }

        voiceRecordings.append(recording)
        hasChanges = true
        HapticManager.shared.success()
    }

    func removeVoiceRecording(at index: Int) {
        guard index < voiceRecordings.count else { return }
        voiceRecordings.remove(at: index)
        hasChanges = true
        HapticManager.shared.lightImpact()
    }
}

// MARK: - Track Changes

extension ReflectionEditorViewModel {
    func trackChanges() {
        hasChanges = true
    }
}
