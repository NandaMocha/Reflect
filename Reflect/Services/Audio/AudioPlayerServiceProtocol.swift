import Foundation
import Combine

enum AudioPlaybackState: Equatable {
    case idle
    case loading
    case playing(currentTime: TimeInterval, duration: TimeInterval)
    case paused(currentTime: TimeInterval, duration: TimeInterval)
    case finished
    case error(String)

    var isPlaying: Bool {
        if case .playing = self {
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

    var currentTime: TimeInterval? {
        switch self {
        case .playing(let time, _), .paused(let time, _):
            return time
        default:
            return nil
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .playing(_, let duration), .paused(_, let duration):
            return duration
        default:
            return nil
        }
    }

    var progress: Double {
        guard let current = currentTime, let total = duration, total > 0 else {
            return 0
        }
        return current / total
    }
}

protocol AudioPlayerServiceProtocol {
    var playbackState: AudioPlaybackState { get }
    var playbackStatePublisher: AnyPublisher<AudioPlaybackState, Never> { get }

    func play(data: Data) async throws
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
}
