import AVFoundation
import SwiftUI
import UIKit

/// The single, reusable camera-reflection flow. Every camera-reflection entry point attaches this
/// modifier and just flips `isPresented` true to start — the intro sheet (first run), front/back
/// choice, camera-permission gating, denied → Settings alert, and camera presentation all live here
/// so no call site duplicates the logic.
///
/// State machine when started:
/// - `.denied` / `.restricted` → show the "open Settings" alert (opened again while denied).
/// - `.authorized` → intro if not yet seen, else straight to the camera.
/// - `.notDetermined` → intro if not yet seen; else request access, then open or show the alert.
///
/// Intro "Continue": persist the choice, then request access when needed — granted opens the camera,
/// denied simply dismisses (no black camera).
struct CameraReflectionFlowModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPhotoPicked: (UIImage) -> Void
    let onVideoPicked: (URL, UIImage, TimeInterval) -> Void

    private enum Stage: Int, Identifiable {
        case intro
        case camera
        var id: Int { rawValue }
    }

    /// Deferred until the intro cover finishes dismissing — presenting a new cover while one is on
    /// screen is unreliable, so the intro → camera / denied hand-off happens in `onDismiss`.
    private enum PendingTransition {
        case openCamera
        case showDenied
    }

    @State private var stage: Stage?
    @State private var pending: PendingTransition?
    @State private var showDeniedAlert = false
    @State private var position: CameraPosition = UserDefaults.standard.preferredCameraPosition() ?? .back

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, active in
                guard active else { return }
                // Consume the trigger; this modifier drives its own presentation state from here.
                isPresented = false
                startFlow()
            }
            .fullScreenCover(item: $stage, onDismiss: runPendingTransition) { stage in
                switch stage {
                case .intro:
                    CameraReflectionIntroView(
                        position: $position,
                        onContinue: { Task { await handleIntroContinue() } },
                        onCancel: { self.stage = nil }
                    )
                case .camera:
                    ImagePickerView(
                        sourceType: .camera,
                        cameraPosition: position,
                        onPhotoPicked: { image in
                            onPhotoPicked(image)
                            self.stage = nil
                        },
                        onVideoPicked: { url, thumbnail, duration in
                            onVideoPicked(url, thumbnail, duration)
                            self.stage = nil
                        }
                    )
                    .ignoresSafeArea()
                }
            }
            .confirmationAlert(
                title: "Camera Access Needed",
                message: "Turn on camera access in Settings to add photo and video reflections.",
                isPresented: $showDeniedAlert,
                confirmButtonTitle: "Open Settings",
                cancelButtonTitle: "Not Now",
                isDestructive: false,
                confirmAction: openSettings
            )
    }

    // MARK: - Flow

    private func startFlow() {
        switch CameraPermission.status {
        case .denied, .restricted:
            showDeniedAlert = true
        case .authorized:
            stage = hasSeenIntro ? .camera : .intro
        case .notDetermined:
            if hasSeenIntro {
                Task { await requestThenOpen() }
            } else {
                stage = .intro
            }
        @unknown default:
            stage = .intro
        }
    }

    @MainActor
    private func handleIntroContinue() async {
        markIntroSeen()
        UserDefaults.standard.setPreferredCameraPosition(position)

        switch CameraPermission.status {
        case .authorized:
            transitionFromIntro(to: .openCamera)
        case .notDetermined:
            let granted = await CameraPermission.requestAccess()
            transitionFromIntro(to: granted ? .openCamera : nil)
        default:
            transitionFromIntro(to: .showDenied)
        }
    }

    @MainActor
    private func requestThenOpen() async {
        let granted = await CameraPermission.requestAccess()
        if granted {
            stage = .camera
        } else {
            showDeniedAlert = true
        }
    }

    /// Dismisses the intro cover; `runPendingTransition` fires after and performs `next` (or nothing
    /// when `next` is nil, i.e. permission was just denied).
    private func transitionFromIntro(to next: PendingTransition?) {
        pending = next
        stage = nil
    }

    private func runPendingTransition() {
        guard let pending else { return }
        self.pending = nil
        switch pending {
        case .openCamera:
            stage = .camera
        case .showDenied:
            showDeniedAlert = true
        }
    }

    // MARK: - Helpers

    private var hasSeenIntro: Bool {
        UserDefaults.standard.bool(forKey: Constants.UserDefaults.hasSeenCameraIntro)
    }

    private func markIntroSeen() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.hasSeenCameraIntro)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {
    /// Attaches the guided camera-reflection flow. Flip `isPresented` true to start it; the modifier
    /// consumes the flag and drives the intro/permission/camera presentation itself.
    func cameraReflectionFlow(
        isPresented: Binding<Bool>,
        onPhotoPicked: @escaping (UIImage) -> Void,
        onVideoPicked: @escaping (URL, UIImage, TimeInterval) -> Void
    ) -> some View {
        modifier(CameraReflectionFlowModifier(
            isPresented: isPresented,
            onPhotoPicked: onPhotoPicked,
            onVideoPicked: onVideoPicked
        ))
    }
}
