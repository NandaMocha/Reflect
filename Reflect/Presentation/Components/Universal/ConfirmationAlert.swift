import SwiftUI

// MARK: - Universal Confirmation Alert Component

/// A reusable confirmation alert component that provides a consistent
/// alert pattern across the application.
struct ConfirmationAlert {
    var title: String
    var message: String
    var confirmButtonTitle: String = "Confirm"
    var cancelButtonTitle: String = "Cancel"
    var isDestructive: Bool = true

    func makeAlert(isPresented: Binding<Bool>, confirmAction: @escaping () -> Void) -> Alert {
        Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .cancel(Text(cancelButtonTitle)) {
                isPresented.wrappedValue = false
            },
            secondaryButton: isDestructive ?
                .destructive(Text(confirmButtonTitle), action: confirmAction) :
                .default(Text(confirmButtonTitle), action: confirmAction)
        )
    }
}

// MARK: - View Extension for Easy Alert Attachment

extension View {
    /// Presents a confirmation alert with standard styling
    func confirmationAlert(
        title: String,
        message: String,
        isPresented: Binding<Bool>,
        confirmButtonTitle: String = "Confirm",
        cancelButtonTitle: String = "Cancel",
        isDestructive: Bool = true,
        confirmAction: @escaping () -> Void
    ) -> some View {
        self.alert(title, isPresented: isPresented) {
            Button(cancelButtonTitle, role: .cancel) {}
            if isDestructive {
                Button(confirmButtonTitle, role: .destructive) {
                    confirmAction()
                }
            } else {
                Button(confirmButtonTitle) {
                    confirmAction()
                }
            }
        } message: {
            Text(message)
        }
    }

    /// Presents a delete confirmation alert with standard styling
    func deleteConfirmationAlert(
        itemName: String,
        isPresented: Binding<Bool>,
        additionalMessage: String? = nil,
        confirmAction: @escaping () -> Void
    ) -> some View {
        let alertTitle = "Delete \(itemName)?"
        let defaultMessage = "Are you sure you want to delete \"\(itemName)\"? This action cannot be undone."
        let message = additionalMessage ?? defaultMessage

        return self.alert(alertTitle, isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                confirmAction()
            }
        } message: {
            Text(message)
        }
    }
}

// MARK: - Standard Alert Configurations

struct StandardAlerts {
    /// Delete confirmation for a single item
    static func deleteItem(
        _ itemName: String,
        additionalInfo: String? = nil
    ) -> (title: String, message: String) {
        let defaultMessage = "Are you sure you want to delete \"\(itemName)\"? This action cannot be undone."
        let message = additionalInfo ?? defaultMessage
        return ("Delete \(itemName)?", message)
    }

    /// Discard changes confirmation
    static func discardChanges() -> (title: String, message: String) {
        ("Discard Changes?", "You have unsaved changes. Are you sure you want to discard them?")
    }

    /// Clear all data confirmation
    static func clearAllData() -> (title: String, message: String) {
        ("Clear All Data?", "This will permanently delete all your learnings, reflections, images, and voice notes. This action cannot be undone.")
    }
}
