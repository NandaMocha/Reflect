import Foundation

/// One participant of a space's `CKShare`, flattened into a CloudKit-free value the
/// presentation layer can render.
///
/// A member is not a record — it exists only on the share — so there's no cached
/// counterpart and no `SpaceStore` model. The members list is always fetched live.
struct SpaceMember: Identifiable, Hashable, Sendable {

    enum Role: Sendable {
        case owner
        case member
    }

    /// Mirrors `CKShare.ParticipantAcceptanceStatus`, minus the cases we never show.
    /// `.invited` covers a participant who has been sent an invite but hasn't opened it.
    enum Status: Sendable {
        case joined
        case invited
    }

    let id: String
    var displayName: String?
    /// The email or phone the invite was sent to. CloudKit only exposes a real name once
    /// the person accepts, so this is what we show for a still-pending invite.
    var contactHandle: String?
    var role: Role
    var status: Status
    var canPost: Bool
    var isMe: Bool

    /// What to render as the row's primary label. Falls back through name → invited
    /// handle → a neutral placeholder, so a row is never blank.
    var displayTitle: String {
        if isMe { return "You" }
        if let displayName, !displayName.isEmpty { return displayName }
        if let contactHandle, !contactHandle.isEmpty { return contactHandle }
        return "A member"
    }

    /// Up to two initials for the avatar, derived from whatever label we're showing.
    var initials: String {
        let source = displayName ?? contactHandle ?? ""
        let words = source
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" })
            .prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
