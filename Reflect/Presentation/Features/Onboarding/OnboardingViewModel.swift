import Foundation
import SwiftData
import Observation

@Observable
final class OnboardingViewModel {
    // MARK: - State
    var isCheckingCloud: Bool = false
    var isRestoring: Bool = false
    var cloudDataSummary: CloudDataSummary?
    var showRestoreOption: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let cloudSyncService: CloudSyncServiceProtocol
    private let restoreUseCase: RestoreFromCloudUseCaseProtocol?

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        cloudSyncService: CloudSyncServiceProtocol? = nil,
        restoreUseCase: RestoreFromCloudUseCaseProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.cloudSyncService = cloudSyncService ?? CloudSyncService()
        self.restoreUseCase = restoreUseCase
    }

    // MARK: - Cloud Check

    @MainActor
    func checkForCloudData() async {
        isCheckingCloud = true
        errorMessage = nil

        do {
            let availability = await cloudSyncService.checkCloudAvailability()

            if availability == .available {
                if let summary = try await cloudSyncService.checkExistingData() {
                    cloudDataSummary = summary
                    showRestoreOption = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isCheckingCloud = false
    }

    @MainActor
    func restoreFromCloud() async -> Bool {
        isRestoring = true
        errorMessage = nil

        do {
            let useCase = restoreUseCase ?? RestoreFromCloudUseCase(
                modelContext: modelContext,
                cloudSyncService: cloudSyncService
            )
            let result = try await useCase.execute()

            isRestoring = false

            if result.success {
                HapticManager.shared.success()
                return true
            } else {
                errorMessage = "Restore failed. Please try again."
                HapticManager.shared.error()
                return false
            }
        } catch {
            isRestoring = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }
}
