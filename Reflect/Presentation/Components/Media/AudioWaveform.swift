import SwiftUI

/// Audio waveform visualization that displays audio levels as animated bars
struct AudioWaveform: View {
    let audioLevels: [CGFloat]  // Normalized 0-1 values
    let isAnimating: Bool
    let color: Color
    let barCount: Int

    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 60

    init(audioLevels: [CGFloat], isAnimating: Bool = true, color: Color = .primaryDefault, barCount: Int = 50) {
        self.audioLevels = audioLevels
        self.isAnimating = isAnimating
        self.color = color
        self.barCount = barCount
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = levelForIndex(index)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: barHeight(level))
                    .animation(isAnimating ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: audioLevels)
            }
        }
        .frame(height: maxBarHeight)
    }

    private func levelForIndex(_ index: Int) -> CGFloat {
        if index < audioLevels.count {
            return audioLevels[index]
        } else if !audioLevels.isEmpty {
            // For bars beyond captured data, interpolate or use nearby values
            let ratio = CGFloat(index) / CGFloat(barCount)
            let dataCount = CGFloat(audioLevels.count)
            let dataIndex = Int(ratio * dataCount)
            return audioLevels[min(dataIndex, audioLevels.count - 1)]
        }
        return 0.1 // Default minimal height
    }

    private func barHeight(_ level: CGFloat) -> CGFloat {
        max(minBarHeight, level * maxBarHeight)
    }
}

#Preview {
    VStack(spacing: 40) {
        // Live recording simulation
        VStack(spacing: 8) {
            Text("Recording")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform(
                audioLevels: [0.2, 0.5, 0.8, 0.6, 0.3, 0.7, 0.9, 0.4, 0.2, 0.6,
                             0.8, 0.5, 0.3, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7,
                             0.4, 0.6, 0.3, 0.8, 0.5, 0.7, 0.4, 0.6, 0.8, 0.3,
                             0.5, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7, 0.4, 0.6,
                             0.8, 0.5, 0.3, 0.7, 0.4, 0.6, 0.8, 0.3, 0.5, 0.7],
                isAnimating: true,
                color: .error
            )
        }

        // Static playback
        VStack(spacing: 8) {
            Text("Playback")
                .font(.caption)
                .foregroundColor(.secondary)

            AudioWaveform(
                audioLevels: [0.3, 0.6, 0.4, 0.8, 0.5, 0.7, 0.3, 0.9, 0.4, 0.6,
                             0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8,
                             0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4,
                             0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8, 0.3, 0.6,
                             0.7, 0.4, 0.5, 0.8, 0.3, 0.6, 0.7, 0.4, 0.5, 0.8],
                isAnimating: false
            )
        }
    }
    .padding()
}
