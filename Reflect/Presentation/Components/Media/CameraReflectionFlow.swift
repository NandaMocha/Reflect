import AVFoundation
import SwiftUI
import UIKit

/// The single, reusable camera-reflection flow. Every camera-reflection entry point attaches this
/// modifier and just flips `isPresented` true to start. Camera-permission gating, the permission
/// primer, the denied → Settings alert, and camera presentation all live here so no call site
/// duplicates the logic.
///
/// When started, `PermissionPrimer` decides from the camera status:
/// - `.settings` (denied / restricted) → the "open Settings" alert.
/// - `.proceed` (authorized) → straight to the camera.
/// - `.primer` (not determined) → the small primer sheet. "Continue" fires the system prompt while
///   the sheet is still fully on screen; granted opens the camera once the sheet has dismissed,
///   refused just closes (no black camera). "Not Now" closes without asking.
///
/// The camera opens on the remembered `preferredCameraPosition`, else the back camera; the user
/// flips with the system camera's own control.
struct CameraReflectionFlowModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPhotoPicked: (UIImage) -> Void
    let onVideoPicked: (URL, UIImage, TimeInterval) -> Void

    /// Deferred until the primer sheet finishes dismissing. Presenting the camera cover while the
    /// sheet is still tearing down is unreliable, so the primer → camera hand-off runs in `onDismiss`.
    private enum PendingTransition {
        case openCamera
    }

    @State private var showPrimer = false
    @State private var showCamera = false
    @State private var pending: PendingTransition?
    @State private var showDeniedAlert = false

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, active in
                guard active else { return }
                // Consume the trigger; this modifier drives its own presentation state from here.
                isPresented = false
                startFlow()
            }
            .sheet(isPresented: $showPrimer, onDismiss: runPendingTransition) {
                PermissionPrimerView(
                    content: .camera,
                    onContinue: { Task { await handlePrimerContinue() } },
                    onNotNow: { showPrimer = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePickerView(
                    sourceType: .camera,
                    cameraPosition: UserDefaults.standard.preferredCameraPosition() ?? .back,
                    onPhotoPicked: { image in
                        onPhotoPicked(image)
                        showCamera = false
                    },
                    onVideoPicked: { url, thumbnail, duration in
                        onVideoPicked(url, thumbnail, duration)
                        showCamera = false
                    }
                )
                .ignoresSafeArea()
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
        switch PermissionPrimer.nextStep(for: [PermissionState(CameraPermission.status)]) {
        case .settings:
            showDeniedAlert = true
        case .proceed:
            showCamera = true
        case .primer:
            showPrimer = true
        }
    }

    /// Asks for access while the primer is still on screen, then dismisses it. Only a grant queues
    /// the camera; a refusal just closes the sheet.
    @MainActor
    private func handlePrimerContinue() async {
        let granted = await CameraPermission.requestAccess()
        pending = granted ? .openCamera : nil
        showPrimer = false
    }

    private func runPendingTransition() {
        guard let pending else { return }
        self.pending = nil
        switch pending {
        case .openCamera:
            showCamera = true
        }
    }

    // MARK: - Helpers

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {
    /// Attaches the guided camera-reflection flow. Flip `isPresented` true to start it; the modifier
    /// consumes the flag and drives the primer/permission/camera presentation itself.
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
