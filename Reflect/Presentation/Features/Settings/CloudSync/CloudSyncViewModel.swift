import Foundation
import SwiftData
import Observation
import Combine

@Observable
final class CloudSyncViewModel {
    // MARK: - State
    var cloudAvailability: CloudAvailability = .temporarilyUnavailable
    var syncStatus: SyncStatus = .idle
    var cloudDataSummary: CloudDataSummary?
    var localDataSummary: LocalDataSummary?
    var errorMessage: String?
    var showRestoreWarning: Bool = false
    var lastSyncDate: Date?

    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let cloudSyncService: CloudSyncServiceProtocol
    private let restoreUseCase: RestoreFromCloudUseCaseProtocol?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        modelContext: ModelContext,
        cloudSyncService: CloudSyncServiceProtocol? = nil,
        restoreUseCase: RestoreFromCloudUseCaseProtocol? = nil
    ) {
        self.modelContext = modelContext
        self.cloudSyncService = cloudSyncService ?? CloudSyncService()
        self.restoreUseCase = restoreUseCase

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        cloudSyncService.syncStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.syncStatus = status
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    var isCloudAvailable: Bool {
        cloudAvailability == .available
    }

    var isSyncing: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

    var isBackingUp: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

    var isRestoring: Bool {
        if case .syncing = syncStatus { return true }
        return false
    }

    var syncProgress: Double {
        if case .syncing(let progress) = syncStatus {
            return progress
        }
        return 0
    }

    var statusMessage: String {
        switch cloudAvailability {
        case .available:
            return "iCloud is available"
        case .noAccount:
            return "No iCloud account signed in"
        case .restricted:
            return "iCloud access is restricted"
        case .networkUnavailable:
            return "Network unavailable"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        }
    }

    var statusIcon: String {
        switch cloudAvailability {
        case .available:
            return "checkmark.icloud"
        case .noAccount, .restricted:
            return "xmark.icloud"
        case .networkUnavailable, .temporarilyUnavailable:
            return "exclamationmark.icloud"
        }
    }

    var lastSyncFormatted: String? {
        guard let date = lastSyncDate else { return nil }
        return date.formatted()
    }

    // MARK: - Actions

    @MainActor
    func checkCloudStatus() async {
        cloudAvailability = await cloudSyncService.checkCloudAvailability()

        if isCloudAvailable {
            await loadCloudDataSummary()
        }

        await loadLocalDataSummary()
        loadLastSyncDate()
    }

    @MainActor
    func loadCloudDataSummary() async {
        do {
            cloudDataSummary = try await cloudSyncService.checkExistingData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadLocalDataSummary() async {
        let learningsDescriptor = FetchDescriptor<Learning>()
        let reflectionsDescriptor = FetchDescriptor<Reflection>()
        let imagesDescriptor = FetchDescriptor<ImageAttachment>()
        let voiceDescriptor = FetchDescriptor<VoiceRecording>()

        let learningsCount = (try? modelContext.fetchCount(learningsDescriptor)) ?? 0
        let reflectionsCount = (try? modelContext.fetchCount(reflectionsDescriptor)) ?? 0
        let imagesCount = (try? modelContext.fetchCount(imagesDescriptor)) ?? 0
        let voiceNotesCount = (try? modelContext.fetchCount(voiceDescriptor)) ?? 0

        localDataSummary = LocalDataSummary(
            learningsCount: learningsCount,
            reflectionsCount: reflectionsCount,
            imagesCount: imagesCount,
            voiceNotesCount: voiceNotesCount
        )
    }

    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: Constants.UserDefaults.lastSyncDate) as? Date
    }

    private func saveLastSyncDate() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: Constants.UserDefaults.lastSyncDate)
    }

    @MainActor
    func backup() async {
        guard isCloudAvailable else {
            errorMessage = "iCloud is not available"
            return
        }

        errorMessage = nil

        do {
            // Fetch all data
            let learningsDescriptor = FetchDescriptor<Learning>()
            let reflectionsDescriptor = FetchDescriptor<Reflection>()

            let learnings = try modelContext.fetch(learningsDescriptor)
            let reflections = try modelContext.fetch(reflectionsDescriptor)

            // Perform backup
            let result = try await cloudSyncService.backup(
                learnings: learnings,
                reflections: reflections
            )

            if result.success {
                saveLastSyncDate()
                await loadCloudDataSummary()
                HapticManager.shared.success()
            } else {
                errorMessage = "Backup completed with \(result.errors.count) errors"
                HapticManager.shared.warning()
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    func confirmRestore() {
        showRestoreWarning = true
    }

    @MainActor
    func restore() async {
        guard isCloudAvailable else {
            errorMessage = "iCloud is not available"
            return
        }

        errorMessage = nil

        do {
            let useCase = restoreUseCase ?? RestoreFromCloudUseCase(
                modelContext: modelContext,
                cloudSyncService: cloudSyncService
            )
            let result = try await useCase.execute()

            if result.success {
                saveLastSyncDate()
                await loadLocalDataSummary()
                HapticManager.shared.success()
            } else {
                errorMessage = "Restore completed with errors"
                HapticManager.shared.warning()
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

// MARK: - Supporting Types

struct LocalDataSummary {
    let learningsCount: Int
    let reflectionsCount: Int
    let imagesCount: Int
    let voiceNotesCount: Int

    var totalItems: Int {
        learningsCount + reflectionsCount + imagesCount + voiceNotesCount
    }

    var isEmpty: Bool {
        totalItems == 0
    }
}
