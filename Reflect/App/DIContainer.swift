import Foundation
import SwiftData

final class DIContainer {
    static let shared = DIContainer()

    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Configuration

    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Repositories

    func makeLearningRepository() -> LearningRepositoryProtocol {
        guard let context = modelContext else {
            fatalError("ModelContext not configured. Call configure(with:) first.")
        }
        return LearningRepository(modelContext: context)
    }

    func makeReflectionRepository() -> ReflectionRepositoryProtocol {
        guard let context = modelContext else {
            fatalError("ModelContext not configured. Call configure(with:) first.")
        }
        return ReflectionRepository(modelContext: context)
    }

    // MARK: - Repositories - Achievement

    func makeBadgeRepository() -> BadgeRepositoryProtocol {
        guard let context = modelContext else {
            fatalError("ModelContext not configured. Call configure(with:) first.")
        }
        return BadgeRepository(modelContext: context)
    }

    func makeMonthlyAchievementRepository() -> MonthlyAchievementRepositoryProtocol {
        guard let context = modelContext else {
            fatalError("ModelContext not configured. Call configure(with:) first.")
        }
        return MonthlyAchievementRepository(modelContext: context)
    }

    // MARK: - Use Cases - Learning

    func makeCreateLearningUseCase() -> CreateLearningUseCaseProtocol {
        CreateLearningUseCase(repository: makeLearningRepository())
    }

    func makeUpdateLearningUseCase() -> UpdateLearningUseCaseProtocol {
        UpdateLearningUseCase(repository: makeLearningRepository())
    }

    func makeDeleteLearningUseCase() -> DeleteLearningUseCaseProtocol {
        DeleteLearningUseCase(repository: makeLearningRepository())
    }

    func makeFetchLearningsUseCase() -> FetchLearningsUseCaseProtocol {
        FetchLearningsUseCase(repository: makeLearningRepository())
    }

    // MARK: - Use Cases - Reflection

    func makeCreateReflectionUseCase() -> CreateReflectionUseCaseProtocol {
        CreateReflectionUseCase(
            reflectionRepository: makeReflectionRepository(),
            learningRepository: makeLearningRepository(),
            imageService: makeImageProcessingService(),
            evaluateBadgesUseCase: makeEvaluateBadgesUseCase()
        )
    }

    func makeUpdateReflectionUseCase() -> UpdateReflectionUseCaseProtocol {
        UpdateReflectionUseCase(
            reflectionRepository: makeReflectionRepository(),
            learningRepository: makeLearningRepository(),
            imageService: makeImageProcessingService()
        )
    }

    func makeDeleteReflectionUseCase() -> DeleteReflectionUseCaseProtocol {
        DeleteReflectionUseCase(reflectionRepository: makeReflectionRepository())
    }

    func makeFetchReflectionsUseCase() -> FetchReflectionsUseCaseProtocol {
        FetchReflectionsUseCase(repository: makeReflectionRepository())
    }

    func makeSearchReflectionsUseCase() -> SearchReflectionsUseCaseProtocol {
        SearchReflectionsUseCase(repository: makeReflectionRepository())
    }

    // MARK: - Services

    func makeSpeechRecognitionService() -> SpeechRecognitionServiceProtocol {
        SpeechRecognitionService()
    }

    func makeAudioRecorderService() -> AudioRecorderServiceProtocol {
        AudioRecorderService()
    }

    func makeAudioPlayerService() -> AudioPlayerServiceProtocol {
        AudioPlayerService()
    }

    func makeImageProcessingService() -> ImageProcessingServiceProtocol {
        ImageProcessingService.shared
    }

    func makeCloudSyncService() -> CloudSyncServiceProtocol {
        CloudSyncService()
    }

    // MARK: - Services - Achievement

    func makeBadgeEvaluationService() -> BadgeEvaluationService {
        BadgeEvaluationService()
    }

    // MARK: - Use Cases - Achievement

    func makeEvaluateBadgesUseCase() -> EvaluateBadgesUseCaseProtocol {
        EvaluateBadgesUseCase(
            badgeEvaluationService: makeBadgeEvaluationService(),
            badgeRepository: makeBadgeRepository()
        )
    }

    // MARK: - ViewModels

    func makeLearningListViewModel() -> LearningListViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return LearningListViewModel(
            fetchLearningsUseCase: makeFetchLearningsUseCase(),
            deleteLearningUseCase: makeDeleteLearningUseCase(),
            modelContext: context
        )
    }

    func makeLearningFormViewModel(learning: Learning? = nil) -> LearningFormViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return LearningFormViewModel(
            modelContext: context,
            createUseCase: makeCreateLearningUseCase(),
            updateUseCase: makeUpdateLearningUseCase()
        )
    }

    func makeReflectionListViewModel(learning: Learning? = nil) -> ReflectionListViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return ReflectionListViewModel(
            modelContext: context,
            learning: learning,
            searchUseCase: makeSearchReflectionsUseCase(),
            deleteUseCase: makeDeleteReflectionUseCase()
        )
    }

    func makeReflectionEditorViewModel(mode: ReflectionEditorViewModel.Mode = .create) -> ReflectionEditorViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return ReflectionEditorViewModel(
            mode: mode,
            modelContext: context,
            createUseCase: makeCreateReflectionUseCase(),
            updateUseCase: makeUpdateReflectionUseCase(),
            imageService: makeImageProcessingService()
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return SettingsViewModel(modelContext: context)
    }

    func makeCloudSyncViewModel() -> CloudSyncViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return CloudSyncViewModel(
            modelContext: context,
            cloudSyncService: makeCloudSyncService()
        )
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        return OnboardingViewModel(
            modelContext: context,
            cloudSyncService: makeCloudSyncService()
        )
    }
}
