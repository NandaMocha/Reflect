import Foundation

/// The `reflect://<host>` URLs the Quick Actions widget opens. Compiled into both the app and
/// the widget extension, so the URL the widget builds and the URL the app parses come from
/// one definition.
enum WidgetDeepLink: String, CaseIterable, Sendable {
    case write
    case camera
    case voice
    case insight

    static let scheme = "reflect"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        // Scheme and host are fixed ASCII literals, so the URL always forms.
        return components.url!
    }

    /// Parses a widget URL. Returns `nil` for another scheme, an empty host, or an unknown host.
    /// Scheme and host match in any case (RFC 3986 treats both as case-insensitive, and iOS
    /// opens the app for `REFLECT://write`).
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased(), !host.isEmpty,
              let link = WidgetDeepLink(rawValue: host) else { return nil }
        self = link
    }
}
