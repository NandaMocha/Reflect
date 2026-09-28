import AVFoundation
import Speech

/// Microphone + speech-recognition authorization for the voice recorder, mirroring `CameraPermission`.
/// The recorder reads status here instead of reaching into `AudioRecorderService` /
/// `SpeechRecognitionService`, and asks through the one-shot requests from its inline primer.
enum VoicePermission {
    /// Current microphone permission.
    static var microphoneStatus: AVAudioApplication.recordPermission {
        #if DEBUG
        if let override = uiTestingOverride { return override == .granted ? .granted : .undetermined }
        #endif
        return AVAudioApplication.shared.recordPermission
    }

    /// Current speech-recognition authorization.
    static var speechStatus: SFSpeechRecognizerAuthorizationStatus {
        #if DEBUG
        if let override = uiTestingOverride { return override == .granted ? .authorized : .notDetermined }
        #endif
        return SFSpeechRecognizer.authorizationStatus()
    }

    /// What the recorder shows before recording, from the current statuses.
    static var nextStep: PermissionPrimer.Step {
        nextStep(microphone: microphoneStatus, speech: speechStatus)
    }

    /// Recording needs the microphone and transcription needs speech, so the primer rule
    /// (`PermissionPrimer.nextStep(for:)`) runs over both.
    static func nextStep(
        microphone: AVAudioApplication.recordPermission,
        speech: SFSpeechRecognizerAuthorizationStatus
    ) -> PermissionPrimer.Step {
        PermissionPrimer.nextStep(for: [PermissionState(microphone), PermissionState(speech)])
    }

    /// Prompts for the microphone (only meaningful while undetermined) and returns whether it was granted.
    static func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Prompts for speech recognition (only meaningful while not determined) and returns whether it
    /// was granted.
    static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - UI test seam

    #if DEBUG
    static let uiTestingLaunchKey = "uiTestingVoicePermission"

    /// `-uiTestingVoicePermission notDetermined|granted` sets both statuses, so a UI test can reach
    /// the primer and the plain recorder. The simulator can reset the microphone but not speech.
    private static var uiTestingOverride: PermissionState? {
        switch UserDefaults.standard.string(forKey: uiTestingLaunchKey) {
        case "notDetermined": .notDetermined
        case "granted": .granted
        default: nil
        }
    }
    #endif
}

// MARK: - Status mapping

extension PermissionState {
    init(_ status: AVAudioApplication.recordPermission) {
        switch status {
        case .granted: self = .granted
        case .denied: self = .denied
        case .undetermined: self = .notDetermined
        // A future status we don't know yet: ask, and let the system prompt decide.
        @unknown default: self = .notDetermined
        }
    }

    init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined: self = .notDetermined
        @unknown default: self = .notDetermined
        }
    }
}
