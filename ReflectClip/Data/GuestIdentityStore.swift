import Foundation
import Security

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
/// 1. **Keychain** (primary) — survives app deletion/reinstall, and is the intended bridge to the
///    full app's install-migration story once `Reflect/Reflect.entitlements` also declares a
///    matching shared `keychain-access-groups` entry. That entitlement change is **out of scope
///    for this ticket** (AC-002's file scope is `ReflectClip/` only, and the repo's hard
///    constraints forbid touching `Reflect/Reflect.entitlements` outside AC-001) — tracked as a
///    follow-up once a ticket actually needs the full app to read this identity.
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
            #if DEBUG
            print("ReflectClip: keychain save failed (status \(keychainStatus)); falling back to App Group mirror")
            #endif
            guard mirrorSaved else {
                throw GuestIdentityStoreError.keychainWrite(keychainStatus)
            }
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

    @discardableResult
    private func saveToAppGroupMirror(_ data: Data) -> Bool {
        guard let defaults = appGroupDefaults else { return false }
        defaults.set(data, forKey: appGroupDefaultsKey)
        return true
    }
}
