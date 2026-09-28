import Foundation
import Combine

protocol SpeechRecognitionServiceProtocol {
    var isRecording: Bool { get }
    var transcribedText: String { get }
    var transcribedTextPublisher: AnyPublisher<String, Never> { get }
    var recordingStatePublisher: AnyPublisher<RecordingState, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    func requestPermission() async -> Bool
    func startRecording(language: Constants.SpeechLanguage) async throws
    func stopRecording() async throws -> VoiceRecordingResult
    func cancelRecording()
    /// Transcribes a recording that is already saved. The fallback for when the live
    /// recognizer did not run or failed. Never throws: the failure is in `outcome`.
    func transcribe(audioData: Data, language: Constants.SpeechLanguage) async -> VoiceRecordingResult
}
