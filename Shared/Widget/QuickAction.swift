import Foundation

/// One deep-linked capture action rendered by both widget sizes.
struct QuickAction: Identifiable, Sendable {
    let link: WidgetDeepLink
    /// Short visible label.
    let title: String
    let systemImage: String
    /// What VoiceOver reads for the action.
    let accessibilityLabel: String
    let accessibilityHint: String
    /// Icon colour. Always one of `WidgetPalette.iconTokens`.
    let tint: WidgetPalette.Token

    var id: WidgetDeepLink { link }
    var url: URL { link.url }

    static let write = QuickAction(
        link: .write, title: "Write", systemImage: "pencil",
        accessibilityLabel: "Write a reflection", accessibilityHint: "Opens Reflect to write a new reflection.",
        tint: .actionWrite)
    static let photo = QuickAction(
        link: .camera, title: "Photo", systemImage: "camera.fill",
        accessibilityLabel: "Photo reflection", accessibilityHint: "Opens Reflect with the camera.",
        tint: .actionPhoto)
    static let voice = QuickAction(
        link: .voice, title: "Voice", systemImage: "waveform",
        accessibilityLabel: "Voice reflection", accessibilityHint: "Opens Reflect to record a voice note.",
        tint: .actionVoice)
    static let insight = QuickAction(
        link: .insight, title: "Insight", systemImage: "lightbulb.fill",
        accessibilityLabel: "Add an insight", accessibilityHint: "Opens Reflect to add an insight.",
        tint: .actionInsight)

    /// Display and VoiceOver order.
    static let all: [QuickAction] = [.write, .photo, .voice, .insight]
}
