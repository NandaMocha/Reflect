import UIKit

/// Which physical camera a camera reflection uses. Single source of truth for the intro-sheet
/// selector, the `UIImagePickerController` device, and the remembered preference.
enum CameraPosition: String, CaseIterable, Identifiable {
    case back
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Back Camera"
        case .front: return "Front Camera"
        }
    }

    /// Short usage hint shown under the title on the camera-selection step.
    var subtitle: String {
        switch self {
        case .back: return "Capture your surroundings, your work, or a scene."
        case .front: return "A quick selfie-style photo or video reflection."
        }
    }

    /// SF Symbol for the option row.
    var icon: String {
        switch self {
        case .back: return "camera.fill"
        case .front: return "person.crop.square.fill"
        }
    }

    var device: UIImagePickerController.CameraDevice {
        switch self {
        case .back: return .rear
        case .front: return .front
        }
    }
}
