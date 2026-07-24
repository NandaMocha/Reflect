import SwiftUI

struct ImageGallery: View {
    let images: [ImageAttachment]
    var onTap: ((ImageAttachment) -> Void)?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Constants.Spacing.sm) {
                ForEach(images.sorted(by: { $0.sortOrder < $1.sortOrder })) { image in
                    ImageGalleryItem(image: image) {
                        onTap?(image)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct ImageGalleryItem: View {
    let image: ImageAttachment
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            Group {
                if let thumbnail = image.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.medium))
        }
    }
}

// MARK: - Attachment Grid (for Editor)

struct AttachmentGrid: View {
    let images: [ImageInput]
    let voiceRecordings: [VoiceRecordingInput]
    var onRemoveImage: ((Int) -> Void)?
    var onRemoveVoice: ((Int) -> Void)?

    var body: some View {
        if images.isEmpty && voiceRecordings.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: Constants.Spacing.sm) {
                // Images
                ForEach(Array(images.enumerated()), id: \.element.id) { index, imageInput in
                    ImageInputThumbnail(image: imageInput.image) {
                        onRemoveImage?(index)
                    }
                }

                // Voice Recordings
                ForEach(Array(voiceRecordings.enumerated()), id: \.element.id) { index, recording in
                    VoiceRecordingThumbnail(recording: recording) {
                        onRemoveVoice?(index)
                    }
                }
            }
        }
    }
}

struct ImageInputThumbnail: View {
    let image: UIImage
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.small))

            if let onRemove = onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .offset(x: 8, y: -8)
            }
        }
    }
}

struct VoiceRecordingThumbnail: View {
    let recording: VoiceRecordingInput
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: Constants.Spacing.xs) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(Color.primaryDefault)

                Text(formatDuration(recording.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, height: 100)
            .background(
                RoundedRectangle(cornerRadius: Constants.CornerRadius.small)
                    .fill(.ultraThinMaterial)
            )

            if let onRemove = onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
                .offset(x: 8, y: -8)
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack {
        AttachmentGrid(
            images: [],
            voiceRecordings: []
        )
    }
    .padding()
}
