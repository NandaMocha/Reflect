import SwiftUI

struct SettingsTermsOfUseView: View {
    var body: some View {
        SettingsLegalDocumentView(
            title: "Terms of Use",
            lastUpdated: "Last updated: October 1, 2026",
            accessibilityID: "legal.termsOfUse"
        ) {
            SettingsLegalSection(
                title: "Agreement",
                text: "By using Reflect you agree to these terms. If you do not agree, please do not use the app. Apple's Licensed Application End User License Agreement also applies to your use of Reflect."
            )

            SettingsLegalSection(
                title: "Your content",
                text: "You own what you write and record in Reflect. You are responsible for keeping a backup of anything you want to keep, for example by turning on iCloud Sync or using Export Data."
            )

            SettingsLegalSection(
                title: "Spaces and feedback links",
                text: "When you share content in a Space or through a feedback link, other people can see it. Only share content you have the right to share. Do not post content that is unlawful, harassing, hateful, sexually explicit, or that infringes someone else's rights. You can report content in a Space, and content that breaks these terms may be removed."
            )

            SettingsLegalSection(
                title: "iCloud and Apple services",
                text: "Sync and sharing depend on your Apple Account and iCloud. They may be unavailable if iCloud is turned off, your iCloud storage is full, or Apple's services are down."
            )

            SettingsLegalSection(
                title: "Changes to the app",
                text: "Features may be added, changed, or removed over time."
            )

            SettingsLegalSection(
                title: "No warranty",
                text: "Reflect is provided \"as is\", without warranties of any kind, to the extent the law allows."
            )

            SettingsLegalSection(
                title: "Limitation of liability",
                text: "To the extent the law allows, the developer is not liable for any loss of data or for indirect or consequential damages that come from using Reflect."
            )

            SettingsLegalSection(
                title: "Changes to these terms",
                text: "If these terms change, the updated version will appear on this screen with a new date. Continuing to use Reflect after a change means you accept the updated terms."
            )
        }
    }
}

#Preview {
    NavigationStack {
        SettingsTermsOfUseView()
    }
}
