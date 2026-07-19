import SwiftUI

extension View {
    /// Applies `.searchable` only when `isActive` is true, so the search field stays hidden
    /// on empty states / when there's nothing to search yet. Flipping `isActive` animates
    /// the field in and out. (Pass `isActive: true` while a search is active but returns no
    /// results, so the user can still clear it.)
    @ViewBuilder
    func searchable(text: Binding<String>, prompt: String, isActive: Bool) -> some View {
        if isActive {
            searchable(text: text, prompt: Text(prompt))
        } else {
            self
        }
    }
}
