import Foundation

protocol CreateInsightUseCaseProtocol {
    func execute(text: String, type: InsightType) async throws -> Insight
}

final class CreateInsightUseCase: CreateInsightUseCaseProtocol {
    private let repository: InsightRepositoryProtocol

    init(repository: InsightRepositoryProtocol) {
        self.repository = repository
    }

    func execute(text: String, type: InsightType) async throws -> Insight {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InsightError.textRequired }
        guard trimmed.count <= Constants.Limits.insightTextMaxLength else { throw InsightError.textTooLong }
        let insight = Insight(text: trimmed, type: type)
        try await repository.create(insight)
        return insight
    }
}

enum InsightError: Error, LocalizedError {
    case textRequired
    case textTooLong
    case notFound

    var errorDescription: String? {
        switch self {
        case .textRequired: return "Insight can't be empty"
        case .textTooLong: return "Insight is too long (max \(Constants.Limits.insightTextMaxLength) characters)"
        case .notFound: return "Insight not found"
        }
    }
}
