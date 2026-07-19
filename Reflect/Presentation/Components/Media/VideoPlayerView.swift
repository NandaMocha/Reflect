import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoData: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                Spacer()

                // Create a temporary file for the video
                if let player = createPlayer() {
                    VideoPlayer(player: player)
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    Text("Unable to load video")
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .padding()
            }
        }
        .background(Color.black)
    }

    private func createPlayer() -> AVPlayer? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")

        do {
            try videoData.write(to: tempURL)
            return AVPlayer(url: tempURL)
        } catch {
            return nil
        }
    }
}

#Preview {
    VideoPlayerView(videoData: Data())
}
