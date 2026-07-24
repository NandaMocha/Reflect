import AVFoundation

/// Camera (video) authorization, mirroring the `withCheckedContinuation` request pattern used by
/// `SpeechRecognitionService` / `AudioRecorderService`. Kept intentionally tiny — the camera-reflection
/// flow only needs the current status and a one-shot request.
enum CameraPermission {
    /// Current video-capture authorization status.
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Prompts for camera access (only meaningful when `status == .notDetermined`) and returns
    /// whether it was granted.
    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
