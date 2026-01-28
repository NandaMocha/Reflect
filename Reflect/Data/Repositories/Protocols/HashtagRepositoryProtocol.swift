import Foundation

protocol HashtagRepositoryProtocol {
    func fetchAll() async throws -> [Hashtag]
    func fetch(name: String) async throws -> Hashtag?
    func fetchOrCreate(name: String) async throws -> Hashtag
    func fetchPopular(limit: Int) async throws -> [Hashtag]
    func search(query: String) async throws -> [Hashtag]
    func delete(_ hashtag: Hashtag) async throws
    func cleanupUnused() async throws
}
