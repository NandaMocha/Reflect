import Foundation

protocol InsightRepositoryProtocol {
    func fetchAll() async throws -> [Insight]
    func fetch(id: UUID) async throws -> Insight?
    func create(_ insight: Insight) async throws
    func update(_ insight: Insight) async throws
    func delete(_ insight: Insight) async throws
}
