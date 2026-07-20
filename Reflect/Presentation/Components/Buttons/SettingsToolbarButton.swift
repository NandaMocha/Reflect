import SwiftUI

/// The Settings (gear) toolbar button, shared across every tab's root so the entry point
/// is consistent app-wide.
struct SettingsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.lightImpact()
            action()
        } label: {
            Image(systemName: "gearshape")
                .font(.title3)
        }
        .accessibilityLabel("Settings")
    }
}
