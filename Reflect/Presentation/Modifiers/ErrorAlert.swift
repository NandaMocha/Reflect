import SwiftUI

extension View {
    /// Presents an error alert bound to an optional message with a real two-way binding, so
    /// any dismissal (button, system, competing presentation) clears the message. Replaces
    /// the fragile `.alert(isPresented: .constant(message != nil))` pattern, which drops
    /// SwiftUI's dismissal write and can re-present or desync.
    func errorAlert(_ message: Binding<String?>, title: String = "Something went wrong") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
