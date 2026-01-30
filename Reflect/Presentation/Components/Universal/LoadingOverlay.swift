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

// MARK: - Native iOS Activity Indicator

/// A native iOS-style activity indicator with smooth animation
struct NativeActivityIndicator: View {
    var size: CGSize = .init(width: 40, height: 40)
    var tint: Color? = nil

    @State private var isRotating = false
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            (tint ?? Color.primaryDefault).opacity(0),
                            (tint ?? Color.primaryDefault).opacity(0.3),
                            (tint ?? Color.primaryDefault).opacity(0.6),
                            (tint ?? Color.primaryDefault)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    )
                )
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    .linear(duration: 1)
                        .repeatForever(autoreverses: false),
                    value: isRotating
                )
                .onAppear { isRotating = true }
        }
    }
}

// MARK: - Native iOS Loading Spinner

/// A smooth, native iOS-style loading spinner
struct NativeLoadingSpinner: View {
    var strokeStyle: StrokeStyle = StrokeStyle(
        lineWidth: 3,
        lineCap: .round
    )
    var tint: Color? = nil

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                (tint ?? Color.primaryDefault),
                style: strokeStyle
            )
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(
                .linear(duration: 0.8)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Loading State with Message

/// A native iOS loading state with optional title and message
struct NativeLoadingState: View {
    var title: String? = nil
    var message: String? = nil
    var style: DisplayStyle = .centered

    enum DisplayStyle {
        case centered
        case fullScreen
        case inline
    }

    var body: some View {
        VStack(spacing: Constants.Spacing.md) {
            NativeLoadingSpinner()

            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(style == .fullScreen ? Constants.Spacing.xl : Constants.Spacing.lg)
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

    /// Shows a native loading overlay with title and message
    func nativeLoadingOverlay(
        isLoading: Bool,
        title: String? = nil,
        message: String? = nil
    ) -> some View {
        self.overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    NativeLoadingState(title: title, message: message)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.CornerRadius.large))
                        .padding()
                }
            }
        }
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    /// Shows a small inline loading indicator
    func inlineLoadingIndicator(
        isLoading: Bool,
        tint: Color? = nil
    ) -> some View {
        self.overlay(alignment: .trailing) {
            if isLoading {
                NativeLoadingSpinner(tint: tint)
                    .frame(width: 20, height: 20)
            }
        }
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

// MARK: - Previews

#Preview("Native Loading Spinner") {
    VStack(spacing: 40) {
        NativeLoadingSpinner()

        NativeActivityIndicator()

        NativeLoadingSpinner(tint: .blue)

        NativeActivityIndicator(tint: .green, size: .init(width: 60, height: 60))
    }
    .padding()
}

#Preview("Native Loading State") {
    VStack(spacing: 40) {
        NativeLoadingState(title: "Loading", message: "Please wait...")

        NativeLoadingState(message: "Syncing data...")
    }
    .padding()
}

#Preview("Loading Overlay") {
    VStack {
        Text("Content under overlay")
            .padding()
    }
    .nativeLoadingOverlay(
        isLoading: true,
        title: "Saving",
        message: "Please wait while we save..."
    )
}
