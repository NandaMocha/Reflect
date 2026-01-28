import Foundation
import AVFoundation
import Combine

final class AudioRecorderService: NSObject, AudioRecorderServiceProtocol {
    private var audioRecorder: AVAudioRecorder?
    private var displayLink: CADisplayLink?
    private var recordingURL: URL?
    private var startTime: Date?

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
            cleanupRecorder()
            return AudioRecordingResult(data: data, duration: duration, url: url)
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
        let level = recorder.averagePower(forChannel: 0)
        let normalizedLevel = max(0, (level + 60) / 60)
        audioLevelSubject.send(normalizedLevel)

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
