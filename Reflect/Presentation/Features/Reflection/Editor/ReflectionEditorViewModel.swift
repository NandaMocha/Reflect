import Foundation
import SwiftData
import SwiftUI
import Observation
import PhotosUI

@Observable
final class ReflectionEditorViewModel {
    // MARK: - Form State
    var title: String = ""
    var content: String = ""
    var selectedLearning: Learning?
    var images: [ImageInput] = []
    var voiceRecordings: [VoiceRecordingInput] = []

    // MARK: - UI State
    var isLoading: Bool = false
    var errorMessage: String?
    var hasChanges: Bool = false
    var showVoiceRecorder: Bool = false
    var showImagePicker: Bool = false
    var selectedPhotoItems: [PhotosPickerItem] = []

    // MARK: - Mode
    enum Mode {
        case create
        case edit(Reflection)
    }

    let mode: Mode
    private var existingReflection: Reflection?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let createUseCase: CreateReflectionUseCaseProtocol
    private let updateUseCase: UpdateReflectionUseCaseProtocol
    private let imageService: ImageProcessingServiceProtocol

    // MARK: - Initialization

    init(
        mode: Mode = .create,
        learningId: UUID? = nil,
        modelContext: ModelContext,
        createUseCase: CreateReflectionUseCaseProtocol? = nil,
        updateUseCase: UpdateReflectionUseCaseProtocol? = nil,
        imageService: ImageProcessingServiceProtocol? = nil
    ) {
        self.mode = mode
        self.modelContext = modelContext

        let reflectionRepo = ReflectionRepository(modelContext: modelContext)
        let learningRepo = LearningRepository(modelContext: modelContext)

        self.createUseCase = createUseCase ?? CreateReflectionUseCase(
            reflectionRepository: reflectionRepo,
            learningRepository: learningRepo,
            imageService: ImageProcessingService.shared
        )
        self.updateUseCase = updateUseCase ?? UpdateReflectionUseCase(
            reflectionRepository: reflectionRepo,
            learningRepository: learningRepo,
            imageService: ImageProcessingService.shared
        )
        self.imageService = imageService ?? ImageProcessingService.shared

        // Setup based on mode
        switch mode {
        case .create:
            if let learningId = learningId {
                loadLearning(learningId)
            }
        case .edit(let reflection):
            configure(with: reflection)
        }
    }

    // MARK: - Setup

    private func configure(with reflection: Reflection) {
        existingReflection = reflection
        title = reflection.title
        content = reflection.plainTextContent
        selectedLearning = reflection.learning

        // Convert existing images to ImageInput
        images = reflection.images.compactMap { attachment in
            guard let uiImage = attachment.image else { return nil }
            return ImageInput(
                id: attachment.id,
                image: uiImage,
                caption: attachment.caption
            )
        }

        // Convert existing voice recordings to VoiceRecordingInput
        voiceRecordings = reflection.voiceRecordings.compactMap { recording in
            guard let audioData = recording.audioData else { return nil }
            return VoiceRecordingInput(
                id: recording.id,
                audioData: audioData,
                transcription: recording.transcription,
                language: recording.language,
                duration: recording.duration
            )
        }
    }

    private func loadLearning(_ id: UUID) {
        let descriptor = FetchDescriptor<Learning>(
            predicate: #Predicate { $0.id == id }
        )
        selectedLearning = try? modelContext.fetch(descriptor).first
    }

    // MARK: - Validation

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
        if voiceRecordings.count > Constants.Limits.maxVoiceNotesPerReflection {
            errors.append("Too many voice recordings (max \(Constants.Limits.maxVoiceNotesPerReflection))")
        }
        return errors
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    // MARK: - Image Actions

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

    // MARK: - Voice Recording Actions

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

    // MARK: - Save Action

    @MainActor
    func save() async -> Bool {
        guard isValid else {
            errorMessage = validationErrors.first
            HapticManager.shared.error()
            return false
        }

        isLoading = true
        errorMessage = nil

        do {
            switch mode {
            case .create:
                let input = CreateReflectionInput(
                    title: title.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    learningId: selectedLearning?.id,
                    images: images,
                    voiceRecordings: voiceRecordings
                )
                try await createUseCase.execute(input: input)

            case .edit(let reflection):
                let input = UpdateReflectionInput(
                    reflectionId: reflection.id,
                    title: title.trimmingCharacters(in: .whitespaces),
                    content: content.trimmingCharacters(in: .whitespaces),
                    learningId: selectedLearning?.id,
                    imagesToAdd: images.filter { img in
                        !reflection.images.contains { $0.id == img.id }
                    },
                    imageIdsToRemove: reflection.images
                        .filter { existing in !images.contains { $0.id == existing.id } }
                        .map { $0.id },
                    voiceRecordingsToAdd: voiceRecordings.filter { rec in
                        !reflection.voiceRecordings.contains { $0.id == rec.id }
                    },
                    voiceRecordingIdsToRemove: reflection.voiceRecordings
                        .filter { existing in !voiceRecordings.contains { $0.id == existing.id } }
                        .map { $0.id }
                )
                try await updateUseCase.execute(input: input)
            }

            isLoading = false
            HapticManager.shared.success()
            return true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    // MARK: - Track Changes

    func trackChanges() {
        hasChanges = true
    }
}
