import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera Media Result

struct CameraMediaResult {
    let image: UIImage?
    let videoURL: URL?
    let thumbnail: UIImage?
    let duration: TimeInterval?

    var isPhoto: Bool { image != nil }
    var isVideo: Bool { videoURL != nil }
}

// MARK: - Custom Camera View

struct CustomCameraView: View {
    @Binding var mediaResult: CameraMediaResult?
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    @StateObject private var camera = CameraController()
    @State private var captureMode: CaptureMode = .photo
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var flashTimer: Timer?

    enum CaptureMode: String, CaseIterable {
        case photo = "Photo"
        case video = "Video"

        var icon: String {
            switch self {
            case .photo: return "camera.fill"
            case .video: return "video.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .onAppear {
                    camera.checkPermissions()
                    camera.configure(mode: captureMode)
                }
                .onDisappear {
                    camera.stopSession()
                }

            // UI Overlay
            VStack {
                // Top bar
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()

                    Spacer()

                    // Flash indicator
                    if camera.hasFlash {
                        Image(systemName: "bolt.slash.fill")
                            .foregroundColor(.white)
                            .padding()
                    }

                    Spacer()

                    // Front/back camera toggle
                    if camera.canSwitchCamera {
                        Button {
                            camera.switchCamera()
                        } label: {
                            Image(systemName: "camera.rotate")
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
                .padding(.top)

                Spacer()

                // Recording duration (only visible when recording)
                if isRecording {
                    Text("\(recordingDuration.formattedDuration)")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                }

                Spacer()

                // Bottom controls
                VStack(spacing: 20) {
                    // Capture mode selector (Photo/Video)
                    Picker("Mode", selection: $captureMode) {
                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: captureMode) { _, newMode in
                        camera.configure(mode: newMode)
                    }

                    // Capture button
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                            )

                        Button {
                            if captureMode == .photo {
                                capturePhoto()
                            } else {
                                if isRecording {
                                    stopRecording()
                                } else {
                                    startRecording()
                                }
                            }
                        } label: {
                            Circle()
                                .fill(captureMode == .video && isRecording ? Color.red : Color.black)
                                .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
                        }
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.bottom, 50)
            }
        }
        .background(Color.black)
        .alert("Camera Access", isPresented: $camera.showPermissionAlert) {
            Button("Settings", action: { openSettings() })
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please grant camera access in Settings to take photos and videos.")
        }
    }

    private func capturePhoto() {
        camera.capturePhoto { image in
            if let image = image {
                // Mirror the image for front camera
                let mirroredImage = camera.cameraPosition == .front ? image.mirror() : image
                mediaResult = CameraMediaResult(
                    image: mirroredImage,
                    videoURL: nil,
                    thumbnail: nil,
                    duration: nil
                )
                dismiss()
            }
        }
    }

    private func startRecording() {
        camera.startRecording { url in
            isRecording = true
            recordingDuration = 0

            // Start timer for recording duration
            flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingDuration += 0.1
                if recordingDuration >= 60 {
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        camera.stopRecording { url, thumbnail, duration in
            isRecording = false
            flashTimer?.invalidate()
            flashTimer = nil
            recordingDuration = 0

            if let url = url {
                mediaResult = CameraMediaResult(
                    image: nil,
                    videoURL: url,
                    thumbnail: thumbnail,
                    duration: duration
                )
                dismiss()
            }
        }
    }

    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Camera Controller

class CameraController: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var showPermissionAlert = false

    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    private var videoRecordingCompletion: ((URL?, UIImage?, TimeInterval?) -> Void)?

    var cameraPosition: AVCaptureDevice.Position = .front
    var currentDevice: AVCaptureDevice?
    var hasFlash: Bool = false
    var canSwitchCamera: Bool = true

    private var videoURL: URL?

    override init() {
        super.init()
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.setupCamera()
                    } else {
                        self.showPermissionAlert = true
                    }
                }
            }
        default:
            showPermissionAlert = true
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return
        }

        currentDevice = device
        cameraPosition = .front
        hasFlash = device.hasFlash
        canSwitchCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil

        do {
            let input = try AVCaptureDeviceInput(device: device)

            session.beginConfiguration()

            if session.canAddInput(input) {
                session.addInput(input)
            }

            // Add photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }

            // Add video output
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.sessionPreset = .high

            session.commitConfiguration()

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }

    func configure(mode: CustomCameraView.CaptureMode) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            if mode == .photo {
                device.activeMode = .photo
            } else {
                // Configure for video
                if device.hasFlash {
                    device.flashMode = .off
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Error configuring camera: \(error)")
        }
    }

    func switchCamera() {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }

        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .front ? .back : .front
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            return
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)

            session.beginConfiguration()
            session.removeInput(currentInput)

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentDevice = newDevice
                cameraPosition = newPosition
                hasFlash = newDevice.hasFlash
            }

            session.commitConfiguration()
        } catch {
            print("Error switching camera: \(error)")
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        photoCaptureCompletion = completion

        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = .off
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording(completion: @escaping (URL?) -> Void) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        videoURL = tempURL

        videoOutput.startRecording(to: tempURL, recordingDelegate: self)
        completion(tempURL)
    }

    func stopRecording(completion: @escaping (URL?, UIImage?, TimeInterval?) -> Void) {
        videoRecordingCompletion = completion
        videoOutput.stopRecording()
    }

    func stopSession() {
        session.stopRunning()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async {
            if let data = photo.fileDataRepresentation(),
               let image = UIImage(data: data) {
                self.photoCaptureCompletion?(image)
            } else {
                self.photoCaptureCompletion?(nil)
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            // Generate thumbnail
            let thumbnail = self.generateThumbnail(from: outputFileURL)
            let duration = self.getVideoDuration(from: outputFileURL)

            self.videoRecordingCompletion?(outputFileURL, thumbnail, duration)
        }
    }

    private func generateThumbnail(from url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 200)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return UIImage(systemName: "video.fill")
        }
    }

    private func getVideoDuration(from url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill

        // Mirror the preview layer for front camera
        if let device = session.inputs.first as? AVCaptureDeviceInput,
           device.device.position == .front {
            previewLayer.connection?.isVideoMirrored = true
        }

        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds

            // Update mirror state
            if let device = session.inputs.first as? AVCaptureDeviceInput {
                previewLayer.connection?.isVideoMirrored = (device.device.position == .front)
            }
        }
    }
}

// MARK: - Extensions

extension TimeInterval {
    var formattedDuration: String {
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension UIImage {
    func mirror() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: .upMirrored)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var result: CameraMediaResult?
    @Previewable @State var isPresented = true

    CustomCameraView(mediaResult: $result, isPresented: $isPresented)
}
