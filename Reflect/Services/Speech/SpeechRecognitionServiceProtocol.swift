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
}
