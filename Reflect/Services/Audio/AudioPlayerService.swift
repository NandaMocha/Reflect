import Foundation
import AVFoundation
import Combine

final class AudioPlayerService: NSObject, AudioPlayerServiceProtocol {
    private var audioPlayer: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var currentData: Data?

    private let playbackStateSubject = CurrentValueSubject<AudioPlaybackState, Never>(.idle)

    var playbackState: AudioPlaybackState {
        playbackStateSubject.value
    }

    var playbackStatePublisher: AnyPublisher<AudioPlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .defaultToSpeaker)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    func play(data: Data) async throws {
        stop()

        currentData = data
        playbackStateSubject.send(.loading)

        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            guard let player = audioPlayer else {
                throw AudioError.playerInitFailed
            }

            player.play()
            startDisplayLink()
            playbackStateSubject.send(.playing(currentTime: 0, duration: player.duration))
        } catch {
            playbackStateSubject.send(.error(error.localizedDescription))
            throw error
        }
    }

    func pause() {
        guard let player = audioPlayer, player.isPlaying else { return }
        player.pause()
        stopDisplayLink()
        playbackStateSubject.send(.paused(currentTime: player.currentTime, duration: player.duration))
    }

    func resume() {
        guard let player = audioPlayer, !player.isPlaying else { return }
        player.play()
        startDisplayLink()
        playbackStateSubject.send(.playing(currentTime: player.currentTime, duration: player.duration))
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentData = nil
        stopDisplayLink()
        playbackStateSubject.send(.idle)
    }

    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = min(max(0, time), player.duration)

        if player.isPlaying {
            playbackStateSubject.send(.playing(currentTime: player.currentTime, duration: player.duration))
        } else {
            playbackStateSubject.send(.paused(currentTime: player.currentTime, duration: player.duration))
        }
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePlaybackTime))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func updatePlaybackTime() {
        guard let player = audioPlayer, player.isPlaying else { return }
        playbackStateSubject.send(.playing(currentTime: player.currentTime, duration: player.duration))
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopDisplayLink()
        playbackStateSubject.send(.finished)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        stopDisplayLink()
        playbackStateSubject.send(.error(error?.localizedDescription ?? "Playback error"))
    }
}

// MARK: - Error

enum AudioError: Error, LocalizedError {
    case playerInitFailed
    case recordingFailed
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .playerInitFailed:
            return "Failed to initialize audio player"
        case .recordingFailed:
            return "Failed to record audio"
        case .fileNotFound:
            return "Audio file not found"
        }
    }
}
