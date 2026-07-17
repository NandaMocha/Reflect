import SwiftUI
import DSWaveformImage
import DSWaveformImageViews

/// Reusable waveform visualization rendered with DSWaveformImage's `Waveform.Style.striped` style
/// via `WaveformLiveCanvas`.
///
/// **Sample convention:** samples are DSWaveformImage's own dB-normalized convention where `0.0` is
/// the loudest sample and `1.0` is silence. The library renderer inverts internally (`1 - sample`),
/// so callers must provide samples already in this `0 = loud, 1 = silent` shape. Do not invert here.
///
/// **Filling the width:** `WaveformLiveCanvas` → `WaveformImageDrawer` maps samples against
/// `samplesNeeded = width * scale` and right-aligns arrays shorter than that (`xOffset =
/// (samplesNeeded - samples.count) / scale`). Our stored arrays are only ~60 values, which would
/// cram into the last few points of the frame. To make the striped waveform span the full width, we
/// resample any input length (nearest-neighbor) to exactly `samplesNeeded` so `xOffset` is 0 and the
/// striped renderer lays a stripe every `(barWidth + spacing) * scale` across the whole frame.
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

        /// Stripe (bar) width.
        var barWidth: CGFloat {
            switch self {
            case .full: return 3
            case .compact: return 2
            case .minimal: return 2
            }
        }

        /// Gap between stripes.
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

    @Environment(\.displayScale) private var displayScale

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let scale = max(displayScale, 1)
            let samplesNeeded = max(1, Int(geo.size.width * scale))

            switch content {
            case .live(let samples):
                stripedCanvas(resample(samples, to: samplesNeeded), color: color, scale: scale)

            case .preview(let samples):
                stripedCanvas(resample(samples, to: samplesNeeded), color: color, scale: scale)

            case .playback(let samples, let progress):
                let resampled = resample(samples, to: samplesNeeded)
                let fraction = CGFloat(min(max(progress, 0), 1))
                ZStack(alignment: .leading) {
                    // Unplayed base layer.
                    stripedCanvas(resampled, color: color.opacity(0.3), scale: scale)
                    // Played overlay, revealed left-to-right up to the progress fraction. Same samples
                    // + config as the base, so stripes line up exactly.
                    stripedCanvas(resampled, color: color, scale: scale)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geo.size.width * fraction)
                        }
                }
                .animation(.linear(duration: 0.1), value: progress)
            }
        }
    }

    // MARK: - Private Helpers

    /// A `WaveformLiveCanvas` configured with the `.striped` style in `color`.
    private func stripedCanvas(_ samples: [Float], color: Color, scale: CGFloat) -> some View {
        WaveformLiveCanvas(
            samples: samples,
            configuration: Waveform.Configuration(
                style: .striped(
                    .init(
                        color: UIColor(color),
                        width: style.barWidth,
                        spacing: style.barSpacing,
                        lineCap: .round
                    )
                ),
                scale: scale,
                verticalScalingFactor: 0.95
            ),
            renderer: LinearWaveformRenderer(),
            shouldDrawSilencePadding: false
        )
    }

    /// Resamples `samples` to exactly `count` values via nearest-neighbor so the striped waveform
    /// spans the full width (see the type doc for why). Substitutes a flat silent waveform when
    /// `samples` is empty (legacy recordings can have no stored samples).
    private func resample(_ samples: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        let source = samples.isEmpty ? [Float](repeating: 1.0, count: count) : samples
        guard source.count != count else { return source }
        return (0..<count).map { i in
            source[min(i * source.count / count, source.count - 1)]
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 32) {
            // Sample convention: 0.0 = loud (tall stripe), 1.0 = silent (short stripe). Includes an
            // explicit 0.1 (loud → tall) and 0.9 (quiet → short) pair to sanity-check the convention.
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

                Text("Preview — empty samples fallback").font(.caption).foregroundStyle(.secondary)
                ReflectWaveform(content: .preview(samples: []), style: .full)
                    .frame(height: 60)
            }
        }
        .padding()
    }
}
