import Foundation

// MARK: - UserDefaults Extensions

extension UserDefaults {
    private static let lastUsedLearningIdKey = "lastUsedLearningId"

    /// Retrieve the last used Learning ID from UserDefaults
    func lastUsedLearningId() -> UUID? {
        guard let uuidString = string(forKey: lastUsedLearningIdKey) else { return nil }
        return UUID(uuidString: uuidString)
    }

    /// Save the last used Learning ID to UserDefaults
    func setLastUsedLearningId(_ uuid: UUID) {
        set(uuid.uuidString, forKey: lastUsedLearningIdKey)
    }

    /// Clear the last used Learning ID
    func clearLastUsedLearningId() {
        removeObject(forKey: lastUsedLearningIdKey)
    }
}
