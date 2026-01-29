import SwiftUI
import PhotosUI
import UIKit

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
}
