import SwiftUI

// MARK: - Toolbar Extension

extension ReflectionEditorView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            cancelButton
        }

        ToolbarItem(placement: .confirmationAction) {
            saveButton
        }
    }

    var cancelButton: some View {
        Button("Cancel") {
            if hasChanges {
                showDiscardAlert = true
            } else {
                dismiss()
            }
        }
    }

    var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.primaryDefault)
                .clipShape(Circle())
        }
        .opacity(isValid && !isSaving ? 1.0 : 0.5)
    }

    var bottomToolbar: some View {
        HStack(spacing: Constants.Spacing.xl) {
            Button { showImagePicker = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 20))
                    Text("Photo")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            Button { showMediaPicker = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                    Text("Video")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            Button { showVoiceRecorder = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                    Text("Voice")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Constants.Spacing.lg)
        .padding(.vertical, Constants.Spacing.sm)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
