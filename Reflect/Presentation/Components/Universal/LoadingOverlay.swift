import SwiftUI

// MARK: - Universal Loading Overlay Modifier

/// A reusable modifier that displays a loading overlay when content is loading
struct UniversalLoadingOverlay: ViewModifier {
    var isLoading: Bool
    var style: LoadingStyle = .default
    var disableInteraction: Bool = true

    enum LoadingStyle {
        case `default`
        case centered
        case inline
        case custom(AnyView)

        @ViewBuilder
        var body: some View {
            switch self {
            case .default, .centered:
                ProgressView()
                    .scaleEffect(1.2)
            case .inline:
                ProgressView()
            case .custom(let view):
                view
            }
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            content

            if isLoading {
                overlayView
            }
        }
        .disabled(isLoading && disableInteraction)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    @ViewBuilder
    private var overlayView: some View {
        switch style {
        case .default:
            Color.black.opacity(0.1)
                .ignoresSafeArea()

            style.body

        case .centered:
            Color.black.opacity(0.1)
                .ignoresSafeArea()

            style.body
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

        case .inline:
            style.body

        case .custom:
            style.body
        }
    }
}

// MARK: - Loading State View

/// A standalone view that displays a loading state
struct LoadingStateView: View {
    var title: String? = nil
    var message: String? = nil
    var style: ViewState = .centered

    enum ViewState {
        case centered
        case withText
        case fullScreen
    }

    var body: some View {
        VStack(spacing: 24) {
            switch style {
            case .centered:
                ProgressView()
                    .scaleEffect(1.5)

            case .withText:
                ProgressView()
                    .scaleEffect(1.2)

                if let message = message {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

            case .fullScreen:
                Spacer()

                ProgressView()
                    .scaleEffect(1.5)

                if let title = title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                if let message = message {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Empty Loading State

/// A simple loading indicator without additional UI
struct SimpleLoadingView: View {
    var scale: CGFloat = 1.0
    var tint: Color? = nil

    var body: some View {
        ProgressView()
            .scaleEffect(scale)
            .tint(tint ?? Color.primaryDefault)
    }
}

// MARK: - View Extensions

extension View {
    /// Adds a loading overlay to the view
    func loadingOverlay(
        isLoading: Bool,
        style: UniversalLoadingOverlay.LoadingStyle = .default,
        disableInteraction: Bool = true
    ) -> some View {
        self.modifier(UniversalLoadingOverlay(
            isLoading: isLoading,
            style: style,
            disableInteraction: disableInteraction
        ))
    }

    /// Adds a centered loading overlay with a background
    func centeredLoadingOverlay(
        isLoading: Bool,
        disableInteraction: Bool = true
    ) -> some View {
        self.modifier(UniversalLoadingOverlay(
            isLoading: isLoading,
            style: .centered,
            disableInteraction: disableInteraction
        ))
    }

    /// Applies an opacity change based on loading state
    func loadingOpacity(_ isLoading: Bool) -> some View {
        self.opacity(isLoading ? 0.6 : 1.0)
            .disabled(isLoading)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - Loading Button Modifier

/// A modifier that shows loading state on a button
struct LoadingButtonStyle: ButtonStyle {
    var isLoading: Bool
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
            }
            .disabled(isLoading || isDisabled)
    }
}

// MARK: - Button Extension

extension Button {
    /// Applies loading state styling to a button
    func loadingStyle(isLoading: Bool) -> some View {
        self.buttonStyle(LoadingButtonStyle(isLoading: isLoading))
    }
}
