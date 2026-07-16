import SwiftUI

/// Reusable waveform visualization rendered with a custom SwiftUI bar renderer.
///
/// **Sample convention:** samples are dB-normalized where `0.0` is the loudest sample and `1.0` is
/// silence (this is `DSWaveformImage`'s own convention, preserved here since the analysis service
/// still produces samples in this shape). This view inverts that convention exactly once — via
/// `amp = 1 - sample` in `amplitudes(from:barCount:)` — when converting a sample into a bar
/// amplitude. Callers must already provide samples in the `0 = loud, 1 = silent` convention; do not
/// invert anywhere else.
///
/// **Why a custom renderer:** `WaveformLiveCanvas` (from `DSWaveformImageViews`) maps one sample to
/// one device pixel and right-aligns short arrays. Our stored sample arrays are only ~60 values, so
/// that renderer crammed them into the last few points of the frame, leaving the rest empty and
/// making playback-progress masking effectively dead. This view instead resamples any input length
/// (via nearest-neighbor) to exactly the number of bars that fit the available width, so the
/// waveform always spans the full frame and progress highlighting is deterministic.
///
/// Fills its proposed frame — callers control size via `.frame(height:)`.
struct ReflectWaveform: View {
    // MARK: - Content

    enum Content {
        /// Continuously updating samples, e.g. while recording.
        case live(samples: [Float])
        /// Fixed samples with a playback progress indicator (0...1).
        case playback(samples: [Float], progress: Double)
        /// Fixed samples with no progress indicator, e.g. a list-row preview.
        case preview(samples: [Float])
    }

    // MARK: - Style

    enum Style {
        case full
        case compact
        case minimal

        var barWidth: CGFloat {
            switch self {
            case .full: return 3
            case .compact: return 2
            case .minimal: return 2
            }
        }

        var barSpacing: CGFloat {
            switch self {
            case .full: return 2
            case .compact: return 1
            case .minimal: return 0
            }
        }
    }

    // MARK: - Properties

    let content: Content
    var style: Style = .full
    var color: Color = .primaryDefault

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let barCount = resolvedBarCount(for: geo.size.width)

            switch content {
            case .live(let samples):
                let amps = amplitudes(from: samples, barCount: barCount)
                bars(amplitudes: amps, height: geo.size.height) { _, amp in
                    color.opacity(0.4 + Double(amp) * 0.6)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: amps)

            case .preview(let samples):
                let amps = amplitudes(from: samples, barCount: barCount)
                bars(amplitudes: amps, height: geo.size.height) { _, amp in
                    color.opacity(0.4 + Double(amp) * 0.6)
                }

            case .playback(let samples, let progress):
                let amps = amplitudes(from: samples, barCount: barCount)
                let clampedProgress = min(max(progress, 0), 1)
                bars(amplitudes: amps, height: geo.size.height) { index, _ in
                    let fraction = barCount > 0 ? Double(index) / Double(barCount) : 0
                    return fraction < clampedProgress ? color : color.opacity(0.3)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Number of bars that fit the available width at this style's bar width + spacing.
    private func resolvedBarCount(for width: CGFloat) -> Int {
        max(1, Int((width + style.barSpacing) / (style.barWidth + style.barSpacing)))
    }

    /// Resamples `samples` to exactly `barCount` values via nearest-neighbor, substituting a flat
    /// silent waveform when `samples` is empty (legacy recordings can have no stored samples), then
    /// converts each sample into a normalized amplitude fraction. `amp = 1 - sample` is applied
    /// exactly once, here — DSWaveformImage's convention is `0 = loud, 1 = silent`, so the returned
    /// amplitude is `0 = silent, 1 = loud`.
    private func amplitudes(from samples: [Float], barCount: Int) -> [Float] {
        guard barCount > 0 else { return [] }
        let source = samples.isEmpty ? [Float](repeating: 1.0, count: barCount) : samples
        guard !source.isEmpty else { return [] }

        return (0..<barCount).map { i in
            let sourceIndex = min((i * source.count) / barCount, source.count - 1)
            let sample = source[sourceIndex]
            return min(max(1 - sample, 0), 1)
        }
    }

    /// Lays out one bar per amplitude, mirrored around the vertical centerline (each bar extends
    /// equally up and down from the row's center, via `HStack`'s default vertical centering).
    @ViewBuilder
    private func bars(
        amplitudes: [Float],
        height: CGFloat,
        color colorForBar: @escaping (Int, Float) -> Color
    ) -> some View {
        HStack(alignment: .center, spacing: style.barSpacing) {
            ForEach(Array(amplitudes.enumerated()), id: \.offset) { index, amp in
                RoundedRectangle(cornerRadius: style.barWidth / 2)
                    .fill(colorForBar(index, amp))
                    .frame(
                        width: style.barWidth,
                        height: max(1.5, CGFloat(amp) * (height / 2)) * 2
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            // Sample convention: 0.0 = loud (tall bar), 1.0 = silent (short bar). Includes an
            // explicit 0.1 (loud → tall) and 0.9 (quiet → short) pair to sanity-check `1 - sample`.
            let sampleWaveform: [Float] = [
                0.7, 0.4, 0.2, 0.5, 0.1, 0.3, 0.6, 0.2, 0.9, 0.4,
                0.1, 0.3, 0.5, 0.2, 0.6, 0.3, 0.1, 0.4, 0.7, 0.2,
                0.3, 0.5, 0.1, 0.6, 0.2, 0.4, 0.9, 0.3, 0.1, 0.5
            ]

            Group {
                Text("Live — full").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .live(samples: sampleWaveform), style: .full)
                    .frame(height: 60)

                Text("Live — compact").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .live(samples: sampleWaveform), style: .compact)
                    .frame(height: 32)

                Text("Live — minimal").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .live(samples: sampleWaveform), style: .minimal)
                    .frame(height: 20)
            }

            Group {
                Text("Playback — full (50%)").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .playback(samples: sampleWaveform, progress: 0.5), style: .full)
                    .frame(height: 60)

                Text("Playback — compact (30%)").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .playback(samples: sampleWaveform, progress: 0.3), style: .compact)
                    .frame(height: 32)

                Text("Playback — minimal (80%)").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .playback(samples: sampleWaveform, progress: 0.8), style: .minimal)
                    .frame(height: 20)
            }

            Group {
                Text("Preview — full").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .preview(samples: sampleWaveform), style: .full)
                    .frame(height: 60)

                Text("Preview — compact").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .preview(samples: sampleWaveform), style: .compact)
                    .frame(height: 32)

                Text("Preview — minimal").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .preview(samples: sampleWaveform), style: .minimal)
                    .frame(height: 20)

                Text("Preview — empty samples fallback").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .preview(samples: []), style: .full)
                    .frame(height: 60)
            }
        }
        .padding()
    }
}
