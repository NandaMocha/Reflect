import Foundation

protocol LearningRepositoryProtocol {
    func fetchAll() async throws -> [Learning]
    func fetch(id: UUID) async throws -> Learning?
    func create(_ learning: Learning) async throws
    func update(_ learning: Learning) async throws
    func delete(_ learning: Learning) async throws
    func reorder(_ learnings: [Learning]) async throws
}
