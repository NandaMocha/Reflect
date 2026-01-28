import Foundation
import SwiftData

@Observable
final class LearningListViewModel {
    var learnings: [Learning] = []
    var isLoading = false
    var error: Error?
    var showAddLearning = false
    var learningToEdit: Learning?
    var learningToDelete: Learning?
    var showDeleteAlert = false

    private let fetchLearningsUseCase: FetchLearningsUseCaseProtocol
    private let deleteLearningUseCase: DeleteLearningUseCaseProtocol
    private let modelContext: ModelContext

    init(
        fetchLearningsUseCase: FetchLearningsUseCaseProtocol,
        deleteLearningUseCase: DeleteLearningUseCaseProtocol,
        modelContext: ModelContext
    ) {
        self.fetchLearningsUseCase = fetchLearningsUseCase
        self.deleteLearningUseCase = deleteLearningUseCase
        self.modelContext = modelContext
    }

    @MainActor
    func loadLearnings() async {
        isLoading = true
        error = nil

        do {
            learnings = try await fetchLearningsUseCase.execute()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    @MainActor
    func deleteLearning(_ learning: Learning) async {
        do {
            try await deleteLearningUseCase.execute(learning: learning)
            await loadLearnings()
            HapticManager.shared.success()
        } catch {
            self.error = error
            HapticManager.shared.error()
        }
    }

    func confirmDelete(_ learning: Learning) {
        learningToDelete = learning
        showDeleteAlert = true
    }

    func editLearning(_ learning: Learning) {
        learningToEdit = learning
    }

    func addLearning() {
        showAddLearning = true
        HapticManager.shared.lightImpact()
    }
}
