import SwiftUI

/// Unified audio waveform visualization component
///
/// Supports multiple display modes:
/// - **Live recording**: Real-time animated bars based on audio levels
/// - **Static playback**: Fixed bars showing overall waveform
/// - **Progress tracking**: Bars show played vs unplayed portions
///
/// Usage Examples:
/// ```swift
/// // Live recording (red accent)
/// AudioWaveform(mode: .live(audioLevels: $audioLevels), color: .error)
///
/// // Static playback (primary color)
/// AudioWaveform(mode: .static(audioLevels: levels))
///
/// // With progress tracking
/// AudioWaveform(mode: .progress(audioLevels: levels, progress: 0.5))
///
/// // Compact inline version
/// AudioWaveform(mode: .compact(barCount: 20), style: .minimal)
/// ```
struct AudioWaveform: View {
    @State private var mode: WaveformMode
    let style: WaveformStyle
    let color: Color

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                waveformBar(at: index)
            }
        }
        .frame(height: style.barHeight)
        .id(animationId) // Force refresh when progress changes
    }

    // MARK: - Equatable for updates
    // Note: View identity is properly tracked through id: \.self in ForEach

    // Computed property to force view updates when animating values change
    private var animationId: String {
        switch mode {
        case .live(let binding):
            return "live-\(binding.wrappedValue.count)-\(binding.wrappedValue.first ?? 0)"
        case .progress(_, let progress):
            return "progress-\(progress)"
        default:
            return "static"
        }
    }

    // MARK: - Computed Properties

    private var barCount: Int {
        switch mode {
        case .live(let binding):
            return max(1, binding.wrappedValue.count)
        case .statics(let levels):
            return max(minBarCount, levels.count)
        case .progress(let levels, _):
            return max(minBarCount, levels.count)
        case .compact(let count):
            return count
        }
    }

    private var minBarCount: Int {
        switch mode {
        case .live, .compact:
            return 1
        case .statics, .progress:
            return 20
        }
    }

    private var barSpacing: CGFloat {
        switch style {
        case .full: return 2
        case .compact: return 1
        case .minimal: return 0
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func waveformBar(at index: Int) -> some View {
        let (height, opacity, isPlayed) = barProperties(at: index)

        RoundedRectangle(cornerRadius: style.cornerRadius)
            .fill(barFillColor(isPlayed: isPlayed))
            .frame(width: style.barWidth, height: height)
            .opacity(opacity)
            .animation(barAnimation, value: barAnimationValue)
    }

    private func barFillColor(isPlayed: Bool) -> Color {
        switch style {
        case .full, .minimal:
            return color.opacity(isPlayed ? 1.0 : 0.3)
        case .compact:
            return color.opacity(isPlayed ? 0.8 : 0.4)
        }
    }

    // MARK: - Properties

    private func barProperties(at index: Int) -> (height: CGFloat, opacity: CGFloat, isPlayed: Bool) {
        let level = normalizedLevel(at: index)

        let height: CGFloat
        let opacity: CGFloat
        let isPlayed: Bool

        switch mode {
        case .live:
            height = style.barHeight * level
            opacity = 1.0
            isPlayed = false
        case .statics:
            height = style.barHeight * level
            opacity = 1.0
            isPlayed = false
        case .progress(_, let progress):
            height = style.barHeight * level
            opacity = 1.0
            isPlayed = Double(index) / Double(barCount) < progress
        case .compact:
            height = style.barHeight * level
            opacity = 1.0
            isPlayed = false
        }

        return (height, opacity, isPlayed)
    }

    private func normalizedLevel(at index: Int) -> CGFloat {
        switch mode {
        case .live(let binding):
            if index < binding.wrappedValue.count {
                return binding.wrappedValue[index]
            }
            return 0.1
        case .statics(let levels):
            if index < levels.count {
                return levels[index]
            }
            return 0.1
        case .progress(let levels, _):
            if index < levels.count {
                return levels[index]
            }
            return 0.1
        case .compact:
            // Synthetic waveform for preview
            return syntheticLevel(at: index)
        }
    }

    private func syntheticLevel(at index: Int) -> CGFloat {
        let count = max(20, barCount)
        let normalizedPos = CGFloat(index) / CGFloat(count)
        let baseWave = sin(normalizedPos * .pi * 4) * 0.3 + 0.5
        let variation = sin(normalizedPos * .pi * 10) * 0.2
        return max(0.2, min(1.0, baseWave + variation))
    }

    private var barAnimation: Animation? {
        switch mode {
        case .live:
            return .spring(response: 0.3, dampingFraction: 0.6)
        case .progress:
            return .linear(duration: 0.1)
        default:
            return nil
        }
    }

    private var barAnimationValue: CGFloat {
        switch mode {
        case .live(let binding):
            return CGFloat(binding.wrappedValue.count)
        case .progress(_, let progress):
            return CGFloat(progress)
        default:
            return 0
        }
    }

    // MARK: - Mode Enum

    enum WaveformMode {
        case live(audioLevels: Binding<[CGFloat]>)
        case statics(audioLevels: [CGFloat])
        case progress(audioLevels: [CGFloat], progress: Double)
        case compact(barCount: Int)

        var audioLevels: [CGFloat] {
            switch self {
            case .statics(let levels), .progress(let levels, _):
                return levels
            default:
                return []
            }
        }
    }

    // MARK: - Style Enum

    enum WaveformStyle {
        case full           // Large, for recording/playback screens
        case compact        // Small, for inline previews
        case minimal       // Minimal, for list items

        var barHeight: CGFloat {
            switch self {
            case .full: return 60
            case .compact: return 20
            case .minimal: return 16
            }
        }

        var barWidth: CGFloat {
            switch self {
            case .full: return 3
            case .compact: return 2
            case .minimal: return 2
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .full: return 2
            case .compact: return 1
            case .minimal: return 1
            }
        }
    }

    // MARK: - Initializers

    init(mode: WaveformMode, style: WaveformStyle = .full, color: Color = .primaryDefault) {
        self._mode = State(initialValue: mode)
        self.style = style
        self.color = color
    }

    // Convenience initializers

    /// Live recording waveform with animated bars
    static func live(
        audioLevels: Binding<[CGFloat]>,
        color: Color = .error,
        barCount: Int = 60
    ) -> AudioWaveform {
        AudioWaveform(mode: .live(audioLevels: audioLevels), color: color)
    }

    /// Static waveform for playback/review
    static func playback(
        audioLevels: [CGFloat],
        color: Color = .primaryDefault
    ) -> AudioWaveform {
        AudioWaveform(mode: .statics(audioLevels: audioLevels), color: color)
    }

    /// Waveform with progress indicator
    static func progress(
        audioLevels: [CGFloat],
        progress: Double,
        color: Color = .primaryDefault
    ) -> AudioWaveform {
        AudioWaveform(mode: .progress(audioLevels: audioLevels, progress: progress), color: color)
    }

    /// Compact waveform for inline previews
    static func compact(
        barCount: Int = 15,
        color: Color = .primaryDefault
    ) -> AudioWaveform {
        AudioWaveform(mode: .compact(barCount: barCount), style: .compact, color: color)
    }

    /// Minimal waveform for list items
    static func minimal(
        barCount: Int = 20,
        color: Color = .primaryDefault
    ) -> AudioWaveform {
        AudioWaveform(mode: .compact(barCount: barCount), style: .minimal, color: color)
    }
}

// MARK: - Mirror Style (used by the voice recorder screen)

extension AudioWaveform {
    /// Mirrored waveform: each bar is drawn twice — a full-opacity bar above the centerline
    /// and a dimmer copy below. Exclusively used by the voice recorder screen so the existing
    /// non-mirrored callers (`progress`, `compact`, `minimal`) are untouched.
    static func mirror(
        audioLevels: [CGFloat],
        color: Color = .primaryDefault,
        height: CGFloat = 100,
        barCount: Int = 60
    ) -> some View {
        MirrorWaveformView(levels: audioLevels, color: color, height: height, barCount: barCount)
    }
}

private struct MirrorWaveformView: View {
    let levels: [CGFloat]
    let color: Color
    let height: CGFloat
    let barCount: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                bar(at: index)
            }
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func bar(at index: Int) -> some View {
        let level = index < levels.count ? levels[index] : 0.05
        let halfHeight = max(1.5, level * (height * 0.42))

        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.2 + level * 0.8))
                .frame(width: 4, height: halfHeight)
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.12 + level * 0.5))
                .frame(width: 4, height: halfHeight)
            Spacer(minLength: 0)
        }
        .frame(width: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: level)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Live recording
        VStack(spacing: 8) {
            Text("Live Recording")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform.live(audioLevels: .constant([
                0.2, 0.5, 0.8, 0.6, 0.3, 0.7, 0.9, 0.4, 0.2, 0.6,
                0.8, 0.5, 0.3, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7,
                0.4, 0.6, 0.3, 0.8, 0.5, 0.7, 0.4, 0.6, 0.8, 0.3,
                0.5, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7, 0.4, 0.6,
                0.8, 0.5, 0.3, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7
            ]))
        }

        // Static playback
        VStack(spacing: 8) {
            Text("Playback")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform.playback(audioLevels: [
                0.3, 0.6, 0.4, 0.8, 0.5, 0.7, 0.3, 0.9, 0.4, 0.6,
                0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8,
                0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4,
                0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6,
                0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8
            ])
        }

        // With progress
        VStack(spacing: 8) {
            Text("With 50% Progress")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform.progress(
                audioLevels: [
                    0.3, 0.6, 0.4, 0.8, 0.5, 0.7, 0.3, 0.9, 0.4, 0.6,
                    0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8,
                    0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4,
                    0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6,
                    0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8
                ],
                progress: 0.5
            )
        }

        // Compact preview
        VStack(spacing: 8) {
            Text("Compact Preview")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform.compact()
        }
    }
    .padding()
}
