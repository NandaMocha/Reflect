import Foundation

protocol BadgeRepositoryProtocol {
    func fetchAll() async throws -> [Badge]
    func fetch(id: String) async throws -> Badge?
    func fetchUnlocked() async throws -> [Badge]
    func update(_ badge: Badge) async throws
    func unlock(_ badge: Badge) async throws
}
