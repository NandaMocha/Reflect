import Foundation

protocol ReflectionRepositoryProtocol {
    func fetchAll(limit: Int?, offset: Int?) async throws -> [Reflection]
    func fetch(id: UUID) async throws -> Reflection?
    func fetchByLearning(_ learningId: UUID, limit: Int?, offset: Int?) async throws -> [Reflection]
    func fetchFavorites(limit: Int?, offset: Int?) async throws -> [Reflection]
    func search(query: String, limit: Int?, offset: Int?) async throws -> [Reflection]
    func fetchAll() async throws -> [Reflection]
    func fetchByLearning(_ learningId: UUID) async throws -> [Reflection]
    func fetchFavorites() async throws -> [Reflection]
    func create(_ reflection: Reflection) async throws
    func update(_ reflection: Reflection) async throws
    func delete(_ reflection: Reflection) async throws
    func toggleFavorite(_ reflection: Reflection) async throws
}
