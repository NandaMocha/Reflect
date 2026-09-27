import Foundation
import CoreGraphics

/// Rolling window of levels for the live recording waveform, one value per drawn bar.
///
/// Every `append` moves the window exactly one slot to the left and puts the new value on the
/// right, so the waveform scrolls one bar per level update. Raw levels are shaped by a curve that
/// lifts quiet speech and by a fast-attack / slow-release envelope before they are stored.
///
/// **Sample convention:** `samples` stay in DSWaveformImage's convention (`0` = loudest, `1` =
/// silence), because the recorder screen falls back to them as the stored waveform.
struct LiveWaveformBuffer: Sendable, Equatable {
    // MARK: - Tuning

    struct Tuning: Sendable, Equatable {
        /// Raw levels below this are drawn as silence, so room tone stays a flat line.
        var noiseGate: Float = 0.08
        /// Exponent applied above the gate. Below 1 it lifts quiet levels.
        var gamma: Float = 0.6
        /// Share of the gap closed per tick while the level rises.
        var attack: Float = 0.6
        /// Share of the gap closed per tick while the level falls.
        var release: Float = 0.15
        /// Envelope values below this snap to silence, so a decay ends on the flat baseline.
        var silenceThreshold: Float = 0.005

        static let standard = Tuning()
    }

    /// Seconds between two level updates from `AudioRecorderService`.
    static let emissionInterval: TimeInterval = 0.05

    // MARK: - State

    private(set) var samples: [Float]
    /// Smoothed loudness of the newest bar (`1` = loudest).
    private var envelope: Float = 0
    private let tuning: Tuning

    // MARK: - Initialization

    init(count: Int, tuning: Tuning = .standard) {
        self.samples = Self.silence(max(1, count))
        self.tuning = tuning
    }

    // MARK: - Actions

    /// Takes a raw level (`0...1`, `1` = loudest) and scrolls the window one slot.
    mutating func append(level: Float) {
        let target = Self.curve(level, tuning: tuning)
        let coefficient = target > envelope ? tuning.attack : tuning.release
        envelope += coefficient * (target - envelope)
        if target == 0, envelope < tuning.silenceThreshold { envelope = 0 }

        samples.removeFirst()
        samples.append(max(0, min(1, 1 - envelope)))
    }

    /// Changes the window length. The newest values stay right-aligned, silence fills the left.
    mutating func resize(to count: Int) {
        let count = max(1, count)
        guard count != samples.count else { return }
        if count < samples.count {
            samples = Array(samples.suffix(count))
        } else {
            samples = Self.silence(count - samples.count) + samples
        }
    }

    /// Back to an all-silent window with a resting envelope.
    mutating func reset() {
        samples = Self.silence(samples.count)
        envelope = 0
    }

    // MARK: - Level shaping

    /// Maps a raw level to displayed loudness: noise gate, then a power curve. Both in `0...1`.
    static func curve(_ level: Float, tuning: Tuning = .standard) -> Float {
        guard level.isFinite else { return level == .infinity ? 1 : 0 }
        let clamped = max(0, min(1, level))
        guard clamped >= tuning.noiseGate, tuning.noiseGate < 1 else { return 0 }
        let normalized = (clamped - tuning.noiseGate) / (1 - tuning.noiseGate)
        return max(0, min(1, pow(normalized, tuning.gamma)))
    }

    // MARK: - Layout

    /// Number of bars that fit in `width`. At least 1.
    static func barCount(width: CGFloat, barWidth: CGFloat, barSpacing: CGFloat) -> Int {
        let slotWidth = barWidth + barSpacing
        guard width.isFinite, slotWidth > 0 else { return 1 }
        return max(1, Int(((width + barSpacing) / slotWidth).rounded(.down)))
    }

    /// How far the bars have moved left since the last append: `0` right after it, `slotWidth`
    /// once a full interval has passed. It never exceeds `slotWidth`, so a late update makes the
    /// waveform wait instead of drifting.
    static func scrollOffset(
        elapsed: TimeInterval,
        slotWidth: CGFloat,
        interval: TimeInterval = emissionInterval
    ) -> CGFloat {
        guard interval > 0, !elapsed.isNaN else { return slotWidth }
        let fraction = min(1, max(0, elapsed / interval))
        return slotWidth * CGFloat(fraction)
    }

    /// Left edge of the bar for `samples[index]`. The newest bar starts one slot past the last
    /// visible slot and scrolls into it, so an append never makes a bar jump.
    static func barOriginX(
        index: Int,
        count: Int,
        visibleBars: Int,
        slotWidth: CGFloat,
        scrollOffset: CGFloat
    ) -> CGFloat {
        let slot = index - (count - 1 - visibleBars)
        return CGFloat(slot) * slotWidth - scrollOffset
    }

    /// Bar height for a sample. Silence keeps a `minimum`-high dot as the baseline.
    static func barHeight(
        sample: Float,
        canvasHeight: CGFloat,
        minimum: CGFloat,
        verticalScalingFactor: CGFloat = 0.95
    ) -> CGFloat {
        let loudness = CGFloat(max(0, min(1, 1 - sample)))
        return max(minimum, loudness * canvasHeight * verticalScalingFactor)
    }

    // MARK: - Private Helpers

    private static func silence(_ count: Int) -> [Float] {
        Array(repeating: 1.0, count: count)
    }
}
