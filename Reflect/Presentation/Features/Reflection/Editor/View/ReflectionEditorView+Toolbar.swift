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
        
        ToolbarItem(placement: .bottomBar) {
            bottomToolbar
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
        HStack(spacing: Constants.Spacing.lg) {
            Button { showImagePicker = true } label: {
                Image(systemName: "photo").font(.callout)
            }
            
            Button { showMediaPicker = true } label: {
                Image(systemName: "camera").font(.callout)
            }
            
            Button { showVoiceRecorder = true } label: {
                Image(systemName: "waveform").font(.callout)
            }
        }
        .padding(Constants.Spacing.xxs)
    }
}
