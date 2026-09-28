import AVFoundation

/// Where one system permission stands, reduced to what the primer decision needs.
/// `restricted` (parental controls, MDM) counts as `denied`: the user can't grant it in-app either.
enum PermissionState: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

extension PermissionState {
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined: self = .notDetermined
        // A future status we don't know yet: ask, and let the system prompt decide.
        @unknown default: self = .notDetermined
        }
    }
}

/// Decides what a permission-gated feature shows before it opens. Pure and generic over several
/// permissions so a feature that needs more than one (voice: microphone + speech) uses the same rule.
enum PermissionPrimer {
    enum Step: Sendable, Equatable {
        /// Everything is granted: open the feature.
        case proceed
        /// Something was never asked: show the primer, then the system prompt.
        case primer
        /// Something was refused: the system won't ask again, so point to Settings.
        case settings
    }

    /// Any `denied` wins (asking again is pointless), then any `notDetermined`, else proceed.
    static func nextStep(for states: [PermissionState]) -> Step {
        if states.contains(.denied) { return .settings }
        if states.contains(.notDetermined) { return .primer }
        return .proceed
    }
}
