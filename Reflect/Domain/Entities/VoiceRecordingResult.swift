import Foundation

struct VoiceRecordingResult: Equatable {
    let audioData: Data
    let transcription: String?
    let language: String
    let duration: TimeInterval

    var hasTranscription: Bool {
        transcription != nil && !(transcription?.isEmpty ?? true)
    }

    var formattedDuration: String {
        duration.durationFormatted
    }

    static func == (lhs: VoiceRecordingResult, rhs: VoiceRecordingResult) -> Bool {
        lhs.audioData == rhs.audioData &&
        lhs.transcription == rhs.transcription &&
        lhs.language == rhs.language &&
        lhs.duration == rhs.duration
    }
}

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording(duration: TimeInterval)
    case processing
    case completed(VoiceRecordingResult)
    case failed(String)

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }

    var currentDuration: TimeInterval? {
        if case .recording(let duration) = self {
            return duration
        }
        return nil
    }
}

enum TranscriptionError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case audioEngineError
    case recognitionFailed
    case languageNotSupported
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not authorized. Please enable it in Settings."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .audioEngineError:
            return "Failed to start audio recording."
        case .recognitionFailed:
            return "Speech recognition failed. Please try again."
        case .languageNotSupported:
            return "The selected language is not supported."
        case .cancelled:
            return "Recording was cancelled."
        }
    }
}
