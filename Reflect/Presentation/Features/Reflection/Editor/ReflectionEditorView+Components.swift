import SwiftUI

// MARK: - View Components Extension

extension ReflectionEditorView {
    var contentView: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                        .padding(.bottom, Constants.Spacing.md)

                    titleField
                        .padding(.bottom, Constants.Spacing.xs)

                    contentEditorSection
                        .padding(.bottom, Constants.Spacing.md)

                    if !voiceRecordings.isEmpty {
                        Divider()
                            .opacity(0.7)
                            .padding(.bottom, Constants.Spacing.md)

                        voiceRecordingsSection
                            .padding(.bottom, Constants.Spacing.md)
                    }

                    if !images.isEmpty {
                        Divider()
                            .opacity(0.7)
                            .padding(.bottom, Constants.Spacing.md)

                        imageAttachmentsGallery
                    }

                    if !videos.isEmpty {
                        Divider()
                            .opacity(0.7)
                            .padding(.bottom, Constants.Spacing.md)

                        videoAttachmentsGallery
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
            .opacity(isSaving ? 0.6 : 1.0)
            .disabled(isSaving)

            if isSaving {
                savingOverlay
            }
        }
    }

    // MARK: - Saving Overlay

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: Constants.Spacing.md) {
                NativeLoadingSpinner()

                Text(isEditing ? "Saving Changes" : "Creating Reflection")
                    .font(.headline)
                    .foregroundColor(.primary)

                if !images.isEmpty || !videos.isEmpty {
                    Text("Processing media...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Constants.Spacing.xl)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.large))
        }
        .transition(.opacity)
    }

    var headerView: some View {
        ReflectionEditorHeaderView(
            selectedLearning: selectedLearning,
            selectedDate: selectedDate,
            onSelectLearning: {
                if !learnings.isEmpty {
                    showLearningPicker = true
                }
            },
            onSelectDate: { showDatePicker = true }
        )
    }

    var titleField: some View {
        VStack(spacing: Constants.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if title.isEmpty {
                    Text(defaultTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $title)
                    .font(.title2.weight(.semibold))
                    .focused($focusedField, equals: .title)
                    .onChange(of: title) { _, _ in hasChanges = true }
            }

            Divider()
                .opacity(0.3)
        }
    }

    var voiceRecordingsSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ForEach(Array(voiceRecordings.enumerated()), id: \.offset) { index, recording in
                VoiceRecordingItemView(
                    recording: recording,
                    onPlay: { },
                    onRemove: {
                        voiceRecordings.remove(at: index)
                        hasChanges = true
                    }
                )
            }
        }
    }

    var contentEditorSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Write your reflection here...")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $content)
                    .font(.body)
                    .focused($focusedField, equals: .content)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .onChange(of: content) { _, _ in hasChanges = true }
            }
            .padding(.horizontal, -4)

            Divider()
                .opacity(0.3)
        }
    }

    var imageAttachmentsGallery: some View {
        ImageGridView(items: images) { item, size in
            ImageAttachmentItemView(
                image: item.image,
                onRemove: {
                    if let index = images.firstIndex(where: { $0.id == item.id }) {
                        images.remove(at: index)
                        hasChanges = true
                    }
                }
            )
        }
    }

    var videoAttachmentsGallery: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                VideoAttachmentItemView(
                    thumbnail: video.thumbnailImage,
                    duration: video.duration,
                    onRemove: {
                        videos.remove(at: index)
                        hasChanges = true
                    }
                )
            }
        }
    }
}
