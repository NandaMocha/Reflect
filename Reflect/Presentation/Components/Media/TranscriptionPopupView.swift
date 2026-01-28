import SwiftUI

struct TranscriptionPopupView: View {
    let voiceRecording: VoiceRecording
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primaryDefault)

                    Text("Transcription")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()

                ScrollView {
                    if let transcription = voiceRecording.transcription, !transcription.isEmpty {
                        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                            Text(transcription)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(1.5)

                            Button(action: copyTranscription) {
                                HStack(spacing: Constants.Spacing.sm) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                    Text("Copy Transcription")
                                        .font(.subheadline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.primaryDefault)
                                .foregroundColor(.white)
                                .cornerRadius(Constants.CornerRadius.medium)
                            }
                        }
                        .padding()
                    } else {
                        VStack(spacing: Constants.Spacing.md) {
                            Image(systemName: "text.quote")
                                .font(.title2)
                                .foregroundColor(.secondary)

                            Text("No Transcription Available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }

                Spacer()
            }
            .background(Color(.systemBackground))
        }
    }

    private func copyTranscription() {
        if let transcription = voiceRecording.transcription {
            UIPasteboard.general.string = transcription
            HapticManager.shared.success()
        }
    }
}

#Preview {
    @State var isPresented = true

    let recording = VoiceRecording(
        audioData: nil,
        transcription: "This is a sample transcription of the voice note. It can contain multiple sentences and provides a text representation of the recorded audio.",
        language: "en-US",
        duration: 45
    )

    TranscriptionPopupView(voiceRecording: recording, isPresented: $isPresented)
}
