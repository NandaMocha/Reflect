import SwiftUI

#if DEBUG
/// Small corner ribbon shown only in Debug builds. Debug and Release use separate CloudKit
/// environments (Development vs. Production) that can't see each other's data or share
/// invites — this exists so that's visible at a glance instead of discovered via a confusing
/// "invitation is no longer valid" error. Compiles out entirely in Release/TestFlight/App
/// Store builds, so there's no risk of it ever shipping.
struct DebugBuildBadge: View {
    var body: some View {
        Text("DEBUG")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Constants.Spacing.xs)
            .padding(.vertical, 2)
            .background(.red, in: .capsule)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Pins a "DEBUG" ribbon to the top-trailing corner in Debug builds; a no-op in Release.
    func debugBuildBadge() -> some View {
        overlay(alignment: .topTrailing) {
            DebugBuildBadge()
                .padding(.trailing, Constants.Spacing.xs)
                .padding(.top, Constants.Spacing.xxs)
        }
    }
}
#else
extension View {
    func debugBuildBadge() -> some View { self }
}
#endif
