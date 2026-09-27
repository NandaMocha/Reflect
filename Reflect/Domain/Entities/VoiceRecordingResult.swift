import Foundation

struct VoiceRecordingResult: Equatable {
    let audioData: Data
    let transcription: String?
    let language: String
    let duration: TimeInterval
    let outcome: TranscriptionOutcome

    /// `outcome` defaults to what the text alone says: `.transcribed` when there is text,
    /// `.noSpeechDetected` when there is none.
    init(
        audioData: Data,
        transcription: String?,
        language: String,
        duration: TimeInterval,
        outcome: TranscriptionOutcome? = nil
    ) {
        self.audioData = audioData
        self.transcription = transcription
        self.language = language
        self.duration = duration
        self.outcome = outcome ?? ((transcription ?? "").isEmpty ? .noSpeechDetected : .transcribed)
    }

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
        lhs.duration == rhs.duration &&
        lhs.outcome == rhs.outcome
    }
}

/// How the transcript came out, so a caller can tell "nothing was said" apart from "the
/// recognizer broke" and decide whether to fall back to transcribing the saved audio.
enum TranscriptionOutcome: Equatable {
    /// `transcription` holds the text.
    case transcribed
    /// The recognizer ran and heard no speech.
    case noSpeechDetected
    /// The recognizer ran, or tried to, and failed. `transcription` holds the last partial
    /// text when there was one, which may be incomplete.
    case recognizerFailed(TranscriptionError)
    /// The recognizer never started, for example because stop arrived before start finished.
    case recognizerDidNotRun
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
    case timedOut
    case audioFileUnavailable

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
        case .timedOut:
            return "Speech recognition took too long to finish."
        case .audioFileUnavailable:
            return "The recording could not be read for transcription."
        }
    }
}
