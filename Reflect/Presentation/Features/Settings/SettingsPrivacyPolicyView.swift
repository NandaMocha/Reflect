import SwiftUI

struct SettingsPrivacyPolicyView: View {
    var body: some View {
        SettingsLegalDocumentView(
            title: "Privacy Policy",
            lastUpdated: "Last updated: October 1, 2026",
            accessibilityID: "legal.privacyPolicy"
        ) {
            SettingsLegalSection(
                title: "Overview",
                text: "Reflect is a personal learning journal. It has no accounts, no ads, no analytics, and no third-party trackers. This policy explains where the things you write and record are kept, and when they leave your device."
            )

            SettingsLegalSection(
                title: "Where your data lives",
                text: "Your learnings, reflections, photos, videos, and voice notes are stored on your device. The Reflect widget reads and writes the same data through a storage area shared only between Reflect and its widget on your device."
            )

            SettingsLegalSection(
                title: "iCloud backup and sync",
                text: "If you turn on iCloud Sync, your data is saved in your own private iCloud account using Apple's CloudKit. The developer of Reflect does not run a server for this data and cannot read it. Apple's privacy policy applies to data stored in iCloud."
            )

            SettingsLegalSection(
                title: "Spaces",
                text: "A Space is shared through iCloud. People you invite, and anyone who opens a Space invite link you share, can join the Space and read and add content in it. Your name as shown in iCloud is visible to other members. You can stop sharing or remove members at any time."
            )

            SettingsLegalSection(
                title: "Feedback links",
                text: "When you share a feedback link for a reflection in a Space you own, a read-only copy of that request and its answers, including the authors' display names, is published to Reflect's public iCloud database so the link can open without the full app. Anyone with the link can view it. Guests who answer through the link send their display name and answer through a server run by the developer, which passes them on to iCloud for your Space. Deleting the reflection or the Space removes the published copy."
            )

            SettingsLegalSection(
                title: "Camera, microphone, and speech",
                text: "Reflect uses the camera and microphone only when you take a photo or video or record a voice note. Photos you pick from your library are copied into Reflect; it does not read the rest of your library. Voice notes are transcribed with Apple's speech recognition, on your device when your device supports it. When it does not, Apple processes the audio under Apple's privacy policy."
            )

            SettingsLegalSection(
                title: "Reporting content",
                text: "If you report content in a Space, Reflect opens a pre-filled email with the content's identifiers. Nothing is sent unless you send that email yourself."
            )

            SettingsLegalSection(
                title: "Your choices",
                text: "You can export your data or delete all of it from Settings. Deleting the app removes the data on your device. Data in iCloud can be managed in the iOS Settings app under your Apple Account and iCloud."
            )

            SettingsLegalSection(
                title: "Children",
                text: "Reflect is not directed at children under 13 and does not knowingly collect their personal information."
            )

            SettingsLegalSection(
                title: "Changes to this policy",
                text: "If this policy changes, the updated version will appear on this screen with a new date."
            )
        }
    }
}

#Preview {
    NavigationStack {
        SettingsPrivacyPolicyView()
    }
}
