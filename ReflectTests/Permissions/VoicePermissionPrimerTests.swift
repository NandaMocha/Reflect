import AVFoundation
import Speech
import Testing
@testable import Reflect

struct VoicePermissionPrimerTests {
    // MARK: - Status mapping

    @Test(arguments: [
        (AVAudioApplication.recordPermission.undetermined, PermissionState.notDetermined),
        (.granted, .granted),
        (.denied, .denied)
    ])
    func mapsMicrophonePermission(status: AVAudioApplication.recordPermission, expected: PermissionState) {
        #expect(PermissionState(status) == expected)
    }

    @Test(arguments: [
        (SFSpeechRecognizerAuthorizationStatus.notDetermined, PermissionState.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .denied)
    ])
    func mapsSpeechAuthorization(status: SFSpeechRecognizerAuthorizationStatus, expected: PermissionState) {
        #expect(PermissionState(status) == expected)
    }

    // MARK: - Recorder decision

    @Test func bothGrantedShowsNoPrimer() {
        #expect(VoicePermission.nextStep(microphone: .granted, speech: .authorized) == .proceed)
    }

    @Test func microphoneGrantedAndSpeechNotDeterminedShowsPrimer() {
        #expect(VoicePermission.nextStep(microphone: .granted, speech: .notDetermined) == .primer)
    }

    @Test func microphoneNotDeterminedAndSpeechGrantedShowsPrimer() {
        #expect(VoicePermission.nextStep(microphone: .undetermined, speech: .authorized) == .primer)
    }

    @Test func bothNotDeterminedShowsPrimer() {
        #expect(VoicePermission.nextStep(microphone: .undetermined, speech: .notDetermined) == .primer)
    }

    @Test(arguments: [
        (AVAudioApplication.recordPermission.denied, SFSpeechRecognizerAuthorizationStatus.authorized),
        (.denied, .notDetermined),
        (.granted, .denied),
        (.undetermined, .denied),
        (.granted, .restricted)
    ])
    func anyDeniedShowsNoPrimer(microphone: AVAudioApplication.recordPermission, speech: SFSpeechRecognizerAuthorizationStatus) {
        #expect(VoicePermission.nextStep(microphone: microphone, speech: speech) == .settings)
    }
}
