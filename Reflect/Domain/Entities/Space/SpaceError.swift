import Foundation

enum SpaceError: Error, LocalizedError {
    case iCloudUnavailable
    case nameRequired
    case nameTooLong
    case bodyRequired
    case bodyTooLong
    case notFound
    case notOwner
    case shareFailed(String)
    case acceptFailed(String)
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "Sign in to iCloud to use Spaces."
        case .nameRequired: return "Space name can't be empty."
        case .nameTooLong: return "Space name is too long."
        case .bodyRequired: return "Response can't be empty."
        case .bodyTooLong: return "Response is too long."
        case .notFound: return "That space could not be found."
        case .notOwner: return "Only the space's owner can do that."
        case .shareFailed(let m): return "Couldn't create the invite: \(m)"
        case .acceptFailed(let m): return "Couldn't join the space: \(m)"
        case .syncFailed(let m): return "Sync failed: \(m)"
        }
    }
}
