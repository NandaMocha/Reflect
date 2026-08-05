import Foundation
import Security
import os

/// A guest's stable identity within a single Clip flow: a randomly minted id plus the display
/// name they typed once on the `.needsName` screen.
struct GuestIdentity: Codable, Equatable, Sendable {
    let guestId: UUID
    var displayName: String
}

enum GuestIdentityStoreError: Error, LocalizedError {
    case encodingFailed
    case keychainWrite(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Could not encode the guest identity for storage."
        case .keychainWrite(let status):
            return "Keychain write failed (status \(status))."
        }
    }
}

/// Where a Clip guest's identity lives across launches.
///
/// A guest fills out "what's your name" once, and every later open of the same (or a different)
/// invite link should recognize them without asking again. Two storage layers back this:
///
/// 1. **Keychain** (primary) — survives app deletion/reinstall. `ReflectClip.entitlements`
///    declares no `keychain-access-groups` entry, so writes land in the Clip's own default App ID
///    keychain group — that's sufficient for this ticket's acceptance criterion, which only needs
///    the *Clip* to recognize a returning guest across its own relaunches. Sharing this keychain
///    group with the full app (so install-migration can read it) needs `keychain-access-groups`
///    added to *both* `ReflectClip.entitlements` and `Reflect/Reflect.entitlements`, plus the
///    Keychain Sharing capability added to the Clip's App ID — none of that is in AC-002's scope
///    (`ReflectClip/` only) or on record for AC-H1's capability list, so it's left as a follow-up
///    for whichever ticket actually implements the migration flow.
/// 2. **App Group `UserDefaults`** (fallback mirror) — the App Group is already wired on both
///    targets today, so this is both a safety net if the keychain write fails (simulator quirks,
///    missing entitlement on a given build) and a fast local read path.
protocol GuestIdentityStoring: Sendable {
    /// Reads the persisted identity, preferring the keychain and falling back to the App Group
    /// mirror. Returns `nil` when no guest has completed the name step yet.
    func loadIdentity() -> GuestIdentity?

    /// Persists the identity to both the keychain and the App Group mirror. Throws only if
    /// *both* layers fail to write — a single-layer failure is logged, not propagated, since the
    /// surviving layer still lets the guest continue.
    func save(_ identity: GuestIdentity) throws
}

/// Live `SecItem`-backed implementation. Stateless beyond its constants, so it's safely `Sendable`
/// without `@unchecked` — every stored property is an immutable `Sendable` value.
final class LiveGuestIdentityStore: GuestIdentityStoring, Sendable {

    // MARK: - Constants

    private let keychainService = "xyz.nandamochammad.Reflect.clip.guestIdentity"
    private let keychainAccount = "guestIdentity"
    private let appGroupIdentifier = "group.xyz.nandamochammad.Reflect"
    private let appGroupDefaultsKey = "clip.guestIdentity"
    private let logger = Logger(subsystem: "xyz.nandamochammad.Reflect.Clip", category: "GuestIdentityStore")

    // MARK: - Initialization

    init() {}

    // MARK: - GuestIdentityStoring

    func loadIdentity() -> GuestIdentity? {
        loadFromKeychain() ?? loadFromAppGroupMirror()
    }

    func save(_ identity: GuestIdentity) throws {
        guard let data = try? JSONEncoder().encode(identity) else {
            throw GuestIdentityStoreError.encodingFailed
        }

        let keychainStatus = writeToKeychain(data)
        let mirrorSaved = saveToAppGroupMirror(data)

        if keychainStatus != errSecSuccess {
            logger.error("Keychain save failed (status \(keychainStatus, privacy: .public)); falling back to App Group mirror")
            guard mirrorSaved else {
                logger.error("App Group mirror save also failed — guest identity was not persisted")
                throw GuestIdentityStoreError.keychainWrite(keychainStatus)
            }
        } else if !mirrorSaved {
            // Keychain succeeded, so the guest isn't stranded, but the mirror is the layer most
            // likely to be silently broken during simulator testing (see the type doc comment) —
            // log it independently so that failure mode is never silent.
            logger.error("App Group mirror save failed even though the keychain write succeeded")
        }
    }

    // MARK: - Keychain

    private func keychainQuery(includingValue: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        if includingValue {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
        }
        return query
    }

    private func loadFromKeychain() -> GuestIdentity? {
        let query = keychainQuery(includingValue: true)
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GuestIdentity.self, from: data)
    }

    private func writeToKeychain(_ data: Data) -> OSStatus {
        let baseQuery = keychainQuery(includingValue: false)
        let updateAttributes: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil)
        }
        return updateStatus
    }

    // MARK: - App Group mirror

    private var appGroupDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private func loadFromAppGroupMirror() -> GuestIdentity? {
        guard let data = appGroupDefaults?.data(forKey: appGroupDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(GuestIdentity.self, from: data)
    }

    /// Writes to the App Group mirror and reads back to confirm the write actually landed —
    /// `UserDefaults(suiteName:)` returns a non-nil instance even without the App Group
    /// entitlement, so a nil check alone can't detect a silently-dropped write.
    @discardableResult
    private func saveToAppGroupMirror(_ data: Data) -> Bool {
        guard let defaults = appGroupDefaults else { return false }
        defaults.set(data, forKey: appGroupDefaultsKey)
        return defaults.data(forKey: appGroupDefaultsKey) == data
    }
}
