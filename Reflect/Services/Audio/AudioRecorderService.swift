import Foundation
import AVFoundation
import Combine
import DSWaveformImage

final class AudioRecorderService: NSObject, AudioRecorderServiceProtocol {
    /// Waveform levels are emitted at 20Hz regardless of the display's refresh rate — see
    /// `updateRecordingTime`. With the view's 60-bar window that spans ~3 seconds of audio.
    private static let levelEmissionInterval: CFTimeInterval = 0.05
    /// dBFS treated as silence. Metering runs to -160 dB, but nothing quieter than about
    /// -50 dB is audible room tone, and mapping the full range would leave speech crammed
    /// into the top few percent of the bar height.
    private static let silenceFloorDB: Float = 50

    private var audioRecorder: AVAudioRecorder?
    private var displayLink: CADisplayLink?
    private var recordingURL: URL?
    private var startTime: Date?
    private var pendingPeakLevel: Float = 0
    private var lastLevelEmission: CFTimeInterval = 0

    private let recordingStateSubject = CurrentValueSubject<AudioRecordingState, Never>(.idle)
    private let audioLevelSubject = PassthroughSubject<Float, Never>()

    var recordingState: AudioRecordingState {
        recordingStateSubject.value
    }

    var recordingStatePublisher: AnyPublisher<AudioRecordingState, Never> {
        recordingStateSubject.eraseToAnyPublisher()
    }

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws {
        let hasPermission = await requestPermission()
        guard hasPermission else {
            throw TranscriptionError.notAuthorized
        }

        recordingStateSubject.send(.preparing)

        do {
            try setupAudioSession()
            try setupRecorder()

            guard let recorder = audioRecorder else {
                throw AudioError.recordingFailed
            }

            recorder.record()
            startTime = Date()
            startDisplayLink()
            recordingStateSubject.send(.recording(duration: 0))
        } catch {
            recordingStateSubject.send(.error(error.localizedDescription))
            throw error
        }
    }

    func pauseRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.pause()
        stopDisplayLink()
        recordingStateSubject.send(.paused(duration: recorder.currentTime))
    }

    func resumeRecording() {
        guard let recorder = audioRecorder, !recorder.isRecording else { return }
        recorder.record()
        startDisplayLink()
        recordingStateSubject.send(.recording(duration: recorder.currentTime))
    }

    func stopRecording() async throws -> AudioRecordingResult {
        guard let recorder = audioRecorder, let url = recordingURL else {
            throw AudioError.recordingFailed
        }

        let duration = recorder.currentTime
        recorder.stop()
        stopDisplayLink()

        recordingStateSubject.send(.stopped(duration: duration))

        do {
            let data = try Data(contentsOf: url)
            let waveformSamples = (try? await WaveformAnalyzer().samples(fromAudioAt: url, count: 60)) ?? []
            cleanupRecorder()
            return AudioRecordingResult(data: data, duration: duration, url: url, waveformSamples: waveformSamples)
        } catch {
            cleanupRecorder()
            throw error
        }
    }

    func cancelRecording() {
        audioRecorder?.stop()
        stopDisplayLink()
        cleanupRecorder()
        recordingStateSubject.send(.idle)
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func setupRecorder() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFileName = "recording_\(UUID().uuidString).m4a"
        recordingURL = documentsPath.appendingPathComponent(audioFileName)

        guard let url = recordingURL else {
            throw AudioError.recordingFailed
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
    }

    private func cleanupRecorder() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecorder = nil
        recordingURL = nil
        startTime = nil
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        stopDisplayLink()
        pendingPeakLevel = 0
        lastLevelEmission = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateRecordingTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updateRecordingTime() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()

        // Peak leads the blend: `averagePower` is already smoothed by AVAudioRecorder and on
        // its own squashes speech into a narrow mid band, which draws as a nearly flat
        // waveform. A little average mixed in keeps single-frame spikes from twitching.
        let decibels = recorder.peakPower(forChannel: 0) * 0.7
            + recorder.averagePower(forChannel: 0) * 0.3
        let normalized = max(0, min(1, (decibels + Self.silenceFloorDB) / Self.silenceFloorDB))

        // Hold the loudest reading seen since the last emission, so a transient between
        // emissions still registers instead of being missed by whichever frame we sample on.
        pendingPeakLevel = max(pendingPeakLevel, normalized)

        // Emit on a fixed clock rather than once per frame. A display-link tick is 60Hz or
        // 120Hz depending on the device, and the waveform view keeps a fixed-length rolling
        // window — so emitting per frame made the waveform scroll twice as fast on a
        // ProMotion device, and made the whole window span well under a second on any device.
        let now = CACurrentMediaTime()
        if now - lastLevelEmission >= Self.levelEmissionInterval {
            lastLevelEmission = now
            audioLevelSubject.send(pendingPeakLevel)
            pendingPeakLevel = 0
        }

        recordingStateSubject.send(.recording(duration: recorder.currentTime))
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorderService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            recordingStateSubject.send(.error("Recording did not complete successfully"))
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        recordingStateSubject.send(.error(error?.localizedDescription ?? "Encoding error"))
    }
}
