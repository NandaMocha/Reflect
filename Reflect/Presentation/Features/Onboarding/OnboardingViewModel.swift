import Foundation
import SwiftData
import Observation

@Observable
final class OnboardingViewModel {
    // MARK: - State
    var currentPage: Int = 0
    var isCheckingCloud: Bool = false
    var cloudDataSummary: CloudDataSummary?
    var showRestoreOption: Bool = false
    var errorMessage: String?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let cloudSyncService: CloudSyncServiceProtocol

    // MARK: - Pages

    struct OnboardingPage: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
    }

    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "pencil.and.outline",
            title: "Welcome to ReflectLearn",
            subtitle: "Capture your learning journey with voice, text, and images"
        ),
        OnboardingPage(
            icon: "folder.fill",
            title: "Organize Your Learnings",
            subtitle: "Create categories and find insights instantly"
        ),
        OnboardingPage(
            icon: "mic.fill",
            title: "Speak Your Thoughts",
            subtitle: "Record and transcribe in Indonesian or English"
        )
    ]

    var totalPages: Int {
        showRestoreOption ? pages.count + 1 : pages.count
    }

    var isLastPage: Bool {
        currentPage == totalPages - 1
    }

    var isCloudPage: Bool {
        showRestoreOption && currentPage == pages.count
    }

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        cloudSyncService: CloudSyncServiceProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.cloudSyncService = cloudSyncService ?? CloudSyncService()
    }

    // MARK: - Navigation

    func nextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
            HapticManager.shared.selection()
        }
    }

    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
            HapticManager.shared.selection()
        }
    }

    func goToPage(_ page: Int) {
        guard page >= 0 && page < totalPages else { return }
        currentPage = page
        HapticManager.shared.selection()
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
        isCheckingCloud = true
        errorMessage = nil

        do {
            let result = try await cloudSyncService.restore()

            isCheckingCloud = false

            if result.success {
                HapticManager.shared.success()
                return true
            } else {
                errorMessage = "Restore failed. Please try again."
                HapticManager.shared.error()
                return false
            }
        } catch {
            isCheckingCloud = false
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    // MARK: - Completion

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        HapticManager.shared.success()
    }

    func skipRestore() {
        completeOnboarding()
    }
}
