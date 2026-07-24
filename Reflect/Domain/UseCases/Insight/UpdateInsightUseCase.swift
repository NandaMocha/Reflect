import Foundation

protocol UpdateInsightUseCaseProtocol {
    func execute(insight: Insight, text: String, type: InsightType, followUp: String) async throws
}

final class UpdateInsightUseCase: UpdateInsightUseCaseProtocol {
    private let repository: InsightRepositoryProtocol

    init(repository: InsightRepositoryProtocol) {
        self.repository = repository
    }

    func execute(insight: Insight, text: String, type: InsightType, followUp: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InsightError.textRequired }
        guard trimmed.count <= Constants.Limits.insightTextMaxLength else { throw InsightError.textTooLong }
        insight.text = trimmed
        insight.type = type
        insight.followUp = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        try await repository.update(insight)
    }
}
