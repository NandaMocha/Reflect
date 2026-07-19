import SwiftUI
import UIKit

/// Reusable report action for user-generated Space content (a reflection or a response).
/// Opens the user's mail composer pre-filled with the content identifiers so the developer
/// can act on the report (plan §10). Attach it to reflection rows (T20) and response rows
/// (T21) as a context-menu item or inline button.
///
/// This only *opens* a pre-filled composer — the user still taps Send themselves.
struct ReportContentButton: View {
    /// Human-readable content kind, e.g. "reflection" or "response".
    let contentKind: String
    /// The CloudKit record name of the reported content.
    let contentID: String
    /// The space the content lives in, for context.
    let spaceName: String

    /// Destination for reports. Change this to the app's support/moderation address.
    private let reportEmail = "nanda.mocha@gmail.com"

    var body: some View {
        Button(role: .destructive) {
            openReportMail()
        } label: {
            Label("Report…", systemImage: "exclamationmark.bubble")
        }
    }

    private func openReportMail() {
        let subject = "Report \(contentKind) in \(spaceName)"
        let body = """
        I'd like to report this \(contentKind).

        Space: \(spaceName)
        Content ID: \(contentID)

        Reason:

        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = reportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        // mailto encodes spaces as "+" via query encoding, which some mail clients keep
        // literally; use %20 instead.
        guard let url = components.url
            ?? URL(string: "mailto:\(reportEmail)") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ReportContentButton(contentKind: "reflection", contentID: "ABC-123", spaceName: "Study Group")
}
