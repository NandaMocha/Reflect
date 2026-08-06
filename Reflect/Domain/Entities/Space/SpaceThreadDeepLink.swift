import Foundation

/// A resolved "go straight to this thread" navigation target: the space plus the
/// specific reflection inside it. Used by AC-014's `/f/<token>` universal-link
/// resolution to deep-link past the Spaces list and the space's reflection list,
/// straight into `SpaceThreadView` — mirroring the "push both types onto the same
/// `NavigationPath`" pattern `SpaceListView` already uses for its own
/// `Space.self`/`SpaceReflection.self` destinations.
struct SpaceThreadDeepLink: Equatable {
    let space: Space
    let reflection: SpaceReflection
}
