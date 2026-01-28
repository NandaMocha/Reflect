import Foundation
import Combine

enum AudioRecordingState: Equatable {
    case idle
    case preparing
    case recording(duration: TimeInterval)
    case paused(duration: TimeInterval)
    case stopped(duration: TimeInterval)
    case error(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var isPaused: Bool {
        if case .paused = self {
            return true
        }
        return false
    }

    var currentDuration: TimeInterval? {
        switch self {
        case .recording(let duration), .paused(let duration), .stopped(let duration):
            return duration
        default:
            return nil
        }
    }
}

struct AudioRecordingResult {
    let data: Data
    let duration: TimeInterval
    let url: URL
}

protocol AudioRecorderServiceProtocol {
    var recordingState: AudioRecordingState { get }
    var recordingStatePublisher: AnyPublisher<AudioRecordingState, Never> { get }
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }

    func requestPermission() async -> Bool
    func startRecording() async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording() async throws -> AudioRecordingResult
    func cancelRecording()
}
