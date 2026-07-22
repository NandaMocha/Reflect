import Foundation

// MARK: - UserDefaults Extensions

extension UserDefaults {
    private static let lastUsedLearningIdKey = "lastUsedLearningId"
    private static let preferredCameraPositionKey = "preferredCameraPosition"

    /// The camera (front/back) the user last chose for a camera reflection, if any.
    func preferredCameraPosition() -> CameraPosition? {
        guard let raw = string(forKey: UserDefaults.preferredCameraPositionKey) else { return nil }
        return CameraPosition(rawValue: raw)
    }

    /// Remember the camera (front/back) chosen for camera reflections.
    func setPreferredCameraPosition(_ position: CameraPosition) {
        set(position.rawValue, forKey: UserDefaults.preferredCameraPositionKey)
    }

    /// Retrieve the last used Learning ID from UserDefaults
    func lastUsedLearningId() -> UUID? {
        guard let uuidString = string(forKey: UserDefaults.lastUsedLearningIdKey) else { return nil }
        return UUID(uuidString: uuidString)
    }

    /// Save the last used Learning ID to UserDefaults
    func setLastUsedLearningId(_ uuid: UUID) {
        set(uuid.uuidString, forKey: UserDefaults.lastUsedLearningIdKey)
    }

    /// Clear the last used Learning ID
    func clearLastUsedLearningId() {
        removeObject(forKey: UserDefaults.lastUsedLearningIdKey)
    }
}
