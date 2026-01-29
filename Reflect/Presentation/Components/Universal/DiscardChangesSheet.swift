import SwiftUI

// MARK: - Universal Discard Changes Handler

/// A modifier that handles discard changes confirmation when dismissing a view
struct DiscardChangesHandler: ViewModifier {
    @Binding var isPresented: Bool
    var hasChanges: Bool
    let onDiscard: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .interactiveDismissDisabled(hasChanges)
                .alert("Discard Changes?", isPresented: $isPresented) {
                    Button("Keep Editing", role: .cancel) {}
                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
        } else {
            content
                .alert("Discard Changes?", isPresented: $isPresented) {
                    Button("Keep Editing", role: .cancel) {}
                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds discard changes confirmation when attempting to dismiss
    func discardChangesConfirmation(
        isPresented: Binding<Bool>,
        hasChanges: Bool,
        onDiscard: @escaping () -> Void
    ) -> some View {
        self.modifier(DiscardChangesHandler(
            isPresented: isPresented,
            hasChanges: hasChanges,
            onDiscard: onDiscard
        ))
    }
}

// MARK: - Discard Changes Sheet Component

struct DiscardChangesSheet: View {
    @Binding var isPresented: Bool
    var hasChanges: Bool
    let onDiscard: () -> Void
    let onKeepEditing: () -> Void

    var body: some View {
        EmptyView()
            .alert("Discard Changes?", isPresented: $isPresented) {
                Button("Keep Editing", role: .cancel) {
                    onKeepEditing()
                }
                Button("Discard", role: .destructive) {
                    onDiscard()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
    }
}
