import Foundation
import SwiftData

@preconcurrency @Model
final class VoiceRecording {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var audioData: Data?
    var transcription: String?
    var language: String
    var duration: TimeInterval
    var waveformSamples: [Float] = []
    var sortOrder: Int
    var createdAt: Date

    var reflection: Reflection?

    init(
        id: UUID = UUID(),
        audioData: Data? = nil,
        transcription: String? = nil,
        language: String = "en-US",
        duration: TimeInterval = 0,
        waveformSamples: [Float] = [],
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audioData = audioData
        self.transcription = transcription
        self.language = language
        self.duration = duration
        self.waveformSamples = waveformSamples
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Computed Properties

    var hasTranscription: Bool {
        transcription != nil && !(transcription?.isEmpty ?? true)
    }

    var formattedDuration: String {
        duration.durationFormatted
    }

    var languageDisplayName: String {
        Constants.SpeechLanguage(rawValue: language)?.displayName ?? language
    }

    var languageFlag: String {
        Constants.SpeechLanguage(rawValue: language)?.flag ?? ""
    }
}

// MARK: - Converters

extension VoiceRecording {
    /// Converts the VoiceRecording model to VoiceRecordingInput for use in player views
    func toInput() -> VoiceRecordingInput {
        VoiceRecordingInput(
            id: id,
            existingId: id,
            audioData: audioData ?? Data(),
            transcription: transcription,
            language: language,
            duration: duration,
            waveformSamples: waveformSamples
        )
    }
}
