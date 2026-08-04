import Foundation
import SwiftData

final class DIContainer {
    static let shared = DIContainer()

    private var modelContext: ModelContext?

    /// The one auto-sync coordinator, shared between the repositories that enqueue ops and the
    /// app lifecycle that flushes them. Created lazily on first `makeSyncCoordinator()`.
    private var _syncCoordinator: SyncCoordinator?

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

    // MARK: - Insight

    @MainActor
    func makeInsightRepository() -> InsightRepositoryProtocol {
        InsightRepository(modelContext: InsightStore.container.mainContext)
    }

    @MainActor
    func makeCreateInsightUseCase() -> CreateInsightUseCaseProtocol {
        CreateInsightUseCase(repository: makeInsightRepository())
    }

    @MainActor
    func makeUpdateInsightUseCase() -> UpdateInsightUseCaseProtocol {
        UpdateInsightUseCase(repository: makeInsightRepository())
    }

    @MainActor
    func makeDeleteInsightUseCase() -> DeleteInsightUseCaseProtocol {
        DeleteInsightUseCase(repository: makeInsightRepository())
    }

    @MainActor
    func makeFetchInsightsUseCase() -> FetchInsightsUseCaseProtocol {
        FetchInsightsUseCase(repository: makeInsightRepository())
    }

    @MainActor
    func makeInsightEditorViewModel(mode: InsightEditorViewModel.Mode = .create) -> InsightEditorViewModel {
        InsightEditorViewModel(
            mode: mode,
            createUseCase: makeCreateInsightUseCase(),
            updateUseCase: makeUpdateInsightUseCase()
        )
    }

    @MainActor
    func makeInsightListViewModel() -> InsightListViewModel {
        InsightListViewModel(deleteUseCase: makeDeleteInsightUseCase())
    }

    // MARK: - Space

    func makeSpaceCloudService() -> SpaceCloudServiceProtocol {
        SpaceCloudService()
    }

    @MainActor
    func makeSpaceRepository() -> SpaceRepositoryProtocol {
        SpaceRepository(
            cloudService: makeSpaceCloudService(),
            modelContext: SpaceStore.container.mainContext
        )
    }

    @MainActor
    func makeCreateSpaceUseCase() -> CreateSpaceUseCaseProtocol {
        CreateSpaceUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeFetchSpacesUseCase() -> FetchSpacesUseCaseProtocol {
        FetchSpacesUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeDeleteSpaceUseCase() -> DeleteSpaceUseCaseProtocol {
        DeleteSpaceUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeLeaveSpaceUseCase() -> LeaveSpaceUseCaseProtocol {
        LeaveSpaceUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeAcceptSpaceInviteUseCase() -> AcceptSpaceInviteUseCaseProtocol {
        AcceptSpaceInviteUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeFetchSpaceMembersUseCase() -> FetchSpaceMembersUseCaseProtocol {
        FetchSpaceMembersUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeSpaceFormViewModel() -> SpaceFormViewModel {
        SpaceFormViewModel(
            createUseCase: makeCreateSpaceUseCase()
        )
    }

    @MainActor
    func makeSpaceListViewModel() -> SpaceListViewModel {
        SpaceListViewModel(
            fetchUseCase: makeFetchSpacesUseCase(),
            deleteUseCase: makeDeleteSpaceUseCase(),
            leaveUseCase: makeLeaveSpaceUseCase(),
            repository: makeSpaceRepository(),
            cloudService: makeSpaceCloudService()
        )
    }

    @MainActor
    func makeCreateSpaceReflectionUseCase() -> CreateSpaceReflectionUseCaseProtocol {
        CreateSpaceReflectionUseCase(
            repository: makeSpaceRepository(),
            imageService: makeImageProcessingService()
        )
    }

    @MainActor
    func makeFetchSpaceReflectionsUseCase() -> FetchSpaceReflectionsUseCaseProtocol {
        FetchSpaceReflectionsUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeDeleteOwnSpaceContentUseCase() -> DeleteOwnSpaceContentUseCaseProtocol {
        DeleteOwnSpaceContentUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeUpsertAnswerUseCase() -> UpsertAnswerUseCaseProtocol {
        UpsertAnswerUseCase(
            repository: makeSpaceRepository(),
            imageService: makeImageProcessingService()
        )
    }

    @MainActor
    func makeFetchAnswersUseCase() -> FetchAnswersUseCaseProtocol {
        FetchAnswersUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeDeleteOwnAnswerUseCase() -> DeleteOwnSpaceContentUseCaseProtocol {
        DeleteOwnSpaceContentUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeUpdateReflectionQuestionsUseCase() -> UpdateReflectionQuestionsUseCaseProtocol {
        UpdateReflectionQuestionsUseCase(repository: makeSpaceRepository())
    }

    @MainActor
    func makeSpaceReflectionEditViewModel(reflection: SpaceReflection, space: Space) -> SpaceReflectionEditViewModel {
        SpaceReflectionEditViewModel(
            space: space,
            reflection: reflection,
            updateUseCase: makeUpdateReflectionQuestionsUseCase(),
            fetchAnswersUseCase: makeFetchAnswersUseCase()
        )
    }

    @MainActor
    func makeSpaceDetailViewModel(space: Space) -> SpaceDetailViewModel {
        SpaceDetailViewModel(
            space: space,
            fetchUseCase: makeFetchSpaceReflectionsUseCase(),
            createUseCase: makeCreateSpaceReflectionUseCase(),
            deleteUseCase: makeDeleteOwnSpaceContentUseCase(),
            repository: makeSpaceRepository()
        )
    }

    @MainActor
    func makeSpaceMembersViewModel(space: Space) -> SpaceMembersViewModel {
        SpaceMembersViewModel(
            space: space,
            fetchUseCase: makeFetchSpaceMembersUseCase(),
            repository: makeSpaceRepository()
        )
    }

    @MainActor
    func makeExportFeedbackRequestUseCase() -> ExportFeedbackRequestUseCaseProtocol {
        ExportFeedbackRequestUseCase()
    }

    @MainActor
    func makeSpaceThreadViewModel(reflection: SpaceReflection, space: Space) -> SpaceThreadViewModel {
        SpaceThreadViewModel(
            space: space,
            reflection: reflection,
            fetchUseCase: makeFetchAnswersUseCase(),
            upsertUseCase: makeUpsertAnswerUseCase(),
            deleteUseCase: makeDeleteOwnAnswerUseCase(),
            repository: makeSpaceRepository(),
            exportUseCase: makeExportFeedbackRequestUseCase()
        )
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
            imageService: makeImageProcessingService(),
            evaluateBadgesUseCase: makeEvaluateBadgesUseCase()
        )
    }

    func makeDeleteReflectionUseCase() -> DeleteReflectionUseCaseProtocol {
        DeleteReflectionUseCase(reflectionRepository: makeReflectionRepository())
    }

    func makeMoveReflectionUseCase() -> MoveReflectionUseCaseProtocol {
        MoveReflectionUseCase(
            reflectionRepository: makeReflectionRepository(),
            learningRepository: makeLearningRepository()
        )
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

    /// The shared auto-sync coordinator. Returns the same instance on every call so the
    /// repositories that enqueue and the lifecycle that drains talk to one outbox owner.
    @MainActor
    func makeSyncCoordinator() -> SyncCoordinator {
        if let existing = _syncCoordinator {
            return existing
        }
        guard let context = modelContext else {
            fatalError("ModelContext not configured. Call configure(with:) first.")
        }
        let coordinator = SyncCoordinator(
            cloudSyncService: makeCloudSyncService(),
            modelContext: context
        )
        _syncCoordinator = coordinator
        return coordinator
    }

    // MARK: - Use Cases - Sync

    @MainActor
    func makeRestoreFromCloudUseCase(
        cloudSyncService: CloudSyncServiceProtocol
    ) -> RestoreFromCloudUseCaseProtocol {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        // The service is passed in rather than built here: the caller's view model is already
        // subscribed to that instance's status publisher, and a second instance would restore
        // without ever moving the caller's progress bar.
        return RestoreFromCloudUseCase(
            modelContext: context,
            cloudSyncService: cloudSyncService
        )
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
        let cloudSyncService = makeCloudSyncService()
        return CloudSyncViewModel(
            modelContext: context,
            cloudSyncService: cloudSyncService,
            restoreUseCase: makeRestoreFromCloudUseCase(cloudSyncService: cloudSyncService)
        )
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        guard let context = modelContext else {
            fatalError("ModelContext not configured")
        }
        let cloudSyncService = makeCloudSyncService()
        return OnboardingViewModel(
            modelContext: context,
            cloudSyncService: cloudSyncService,
            restoreUseCase: makeRestoreFromCloudUseCase(cloudSyncService: cloudSyncService)
        )
    }
}
