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
        HStack(spacing: 32) {
            Button { showImagePicker = true } label: {
                Image(systemName: "photo.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }

            Button { showMediaPicker = true } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }

            Button { showVoiceRecorder = true } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}
