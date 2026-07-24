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
    var promptID: String? = nil  // ID of the prompt if reflection was created from a prompt
    var images: [ImageInput] = []
    var videos: [VideoInput] = []
    var voiceRecordings: [VoiceRecordingInput] = []
    var selectedDate: Date = Date()
    var capturedLocation: CapturedLocation?

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
    var existingImageIds: Set<UUID> = []
    var existingVideoIds: Set<UUID> = []

    // MARK: - Dependencies
    let modelContext: ModelContext  // Made internal for use in extensions
    let createUseCase: CreateReflectionUseCaseProtocol
    let updateUseCase: UpdateReflectionUseCaseProtocol
    let imageService: ImageProcessingServiceProtocol


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

        // Create badge evaluation service
        let badgeEvaluationService = BadgeEvaluationService()
        let badgeRepo = BadgeRepository(modelContext: modelContext)
        let evaluateBadgesUseCase = EvaluateBadgesUseCase(
            badgeEvaluationService: badgeEvaluationService,
            badgeRepository: badgeRepo
        )

        self.createUseCase = createUseCase ?? CreateReflectionUseCase(
            reflectionRepository: reflectionRepo,
            learningRepository: learningRepo,
            imageService: ImageProcessingService.shared,
            evaluateBadgesUseCase: evaluateBadgesUseCase
        )
        self.updateUseCase = updateUseCase ?? UpdateReflectionUseCase(
            reflectionRepository: reflectionRepo,
            learningRepository: learningRepo,
            imageService: ImageProcessingService.shared,
            evaluateBadgesUseCase: evaluateBadgesUseCase
        )
        self.imageService = imageService ?? ImageProcessingService.shared

        switch mode {
        case .create:
            break  // Learning is supplied by the view via preselectedLearning + the save bridge.
        case .edit(let reflection):
            configure(with: reflection)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Setup

extension ReflectionEditorViewModel {
    private func configure(with reflection: Reflection) {
        existingReflection = reflection
        title = reflection.title
        content = reflection.plainTextContent
        selectedLearning = reflection.learning
        selectedDate = reflection.createdAt
        if let lat = reflection.locationLatitude, let lon = reflection.locationLongitude {
            capturedLocation = CapturedLocation(latitude: lat, longitude: lon, name: reflection.locationName)
        }

        // Load existing images
        images = reflection.images
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .compactMap { attachment in
                guard let imageData = attachment.imageData,
                      let image = UIImage(data: imageData) else { return nil }
                existingImageIds.insert(attachment.id)
                return ImageInput(
                    id: attachment.id,
                    image: image,
                    caption: attachment.caption
                )
            }

        // Load existing videos
        videos = reflection.videos
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .compactMap { attachment in
                guard let videoData = attachment.videoData,
                      let thumbnailData = attachment.thumbnailData,
                      let thumbnail = UIImage(data: thumbnailData) else { return nil }
                existingVideoIds.insert(attachment.id)
                return VideoInput(
                    id: attachment.id,
                    videoData: videoData,
                    thumbnailImage: thumbnail,
                    duration: attachment.duration,
                    caption: attachment.caption
                )
            }

        // Load existing voice recordings
        voiceRecordings = reflection.voiceRecordings
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .compactMap { recording in
                guard let audioData = recording.audioData else { return nil }
                return VoiceRecordingInput(
                    id: recording.id,
                    existingId: recording.id,
                    audioData: audioData,
                    transcription: recording.transcription,
                    language: recording.language,
                    duration: recording.duration,
                    waveformSamples: recording.waveformSamples
                )
            }
    }

}
