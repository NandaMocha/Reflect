import Foundation

// MARK: - UserDefaults Extensions

extension UserDefaults {
    private static let lastUsedLearningIdKey = "lastUsedLearningId"
    private static let preferredCameraPositionKey = "preferredCameraPosition"
    private static let spaceDisplayNameKey = "spaceDisplayName"

    /// The name the user chose to appear as to other members of shared spaces. `nil` until
    /// they set one. Trimmed; an all-whitespace value reads back as `nil`.
    func spaceDisplayName() -> String? {
        let name = string(forKey: UserDefaults.spaceDisplayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty ?? true) ? nil : name
    }

    /// Save the display name the user appears as in shared spaces.
    func setSpaceDisplayName(_ name: String) {
        set(name, forKey: UserDefaults.spaceDisplayNameKey)
    }

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
