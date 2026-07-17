import Foundation
import DSWaveformImage

/// Extracts real waveform amplitude samples from encoded audio `Data`.
///
/// New recordings store their samples at capture time (see `AudioRecorderService.stopRecording`), but
/// recordings created before that existed have an empty `waveformSamples` array. This loader lets the
/// player screens backfill a real waveform on demand by re-analyzing the stored audio.
///
/// `WaveformAnalyzer` reads from a file URL, so the in-memory `Data` is written to a short-lived temp
/// file for analysis. Samples follow DSWaveformImage's convention (`0 = loud, 1 = silent`).
enum WaveformSampleLoader {
    static func samples(from data: Data, count: Int = 60) async -> [Float] {
        guard !data.isEmpty else { return [] }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")

        do {
            try data.write(to: tempURL)
        } catch {
            return []
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return (try? await WaveformAnalyzer().samples(fromAudioAt: tempURL, count: count)) ?? []
    }
}
