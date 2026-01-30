import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Media Picker Result

enum MediaPickerResult {
    case photo(UIImage)
    case video(URL, thumbnail: UIImage, duration: TimeInterval)
}

// MARK: - Image Picker View with Photo/Video Support

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    var onPhotoPicked: ((UIImage) -> Void)?
    var onVideoPicked: ((URL, UIImage, TimeInterval) -> Void)?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false

        // Support both photo and video
        picker.mediaTypes = ["public.image", "public.movie"]

        // Set camera to front-facing and mirrored
        if sourceType == .camera {
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                picker.cameraDevice = .front
            }
        }

        // Set video quality and max duration
        picker.videoMaximumDuration = 60 // 60 seconds max
        picker.videoQuality = .typeHigh

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Ensure camera stays mirrored for front camera
        if uiViewController.sourceType == .camera,
           uiViewController.cameraDevice == .front {
            if let layer = uiViewController.view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
                layer.connection?.isVideoMirrored = true
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let mediaType = info[.mediaType] as? String {
                if mediaType == "public.image", let image = info[.originalImage] as? UIImage {
                    // Mirror the image if taken with front camera
                    let mirroredImage = picker.cameraDevice == .front ? mirrorImage(image) : image
                    // Call callback synchronously before dismiss
                    parent.onPhotoPicked?(mirroredImage)
                } else if mediaType == "public.movie", let url = info[.mediaURL] as? URL {
                    // Copy video data to a new temp file that won't be deleted
                    if let videoData = try? Data(contentsOf: url) {
                        let permanentTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                        try? videoData.write(to: permanentTempURL)

                        // Generate thumbnail and get duration for video
                        let thumbnail = generateVideoThumbnail(from: permanentTempURL)
                        let duration = getVideoDuration(from: permanentTempURL)

                        // Call callback synchronously before dismiss
                        parent.onVideoPicked?(permanentTempURL, thumbnail, duration)
                    }
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        private func mirrorImage(_ image: UIImage) -> UIImage {
            guard let cgImage = image.cgImage else { return image }

            let width = cgImage.width
            let height = cgImage.height
            let bitsPerComponent = cgImage.bitsPerComponent
            let bytesPerRow = cgImage.bytesPerRow
            let colorSpace = cgImage.colorSpace
            let bitmapInfo = cgImage.bitmapInfo

            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo.rawValue
            ) else { return image }

            context.translateBy(x: CGFloat(width), y: 0)
            context.scaleBy(x: -1, y: 1)

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let mirroredCGImage = context.makeImage() else { return image }

            return UIImage(cgImage: mirroredCGImage, scale: image.scale, orientation: image.imageOrientation)
        }

        private func generateVideoThumbnail(from url: URL) -> UIImage {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 200, height: 200)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            var actualTime = CMTime()

            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: &actualTime)
                return UIImage(cgImage: cgImage)
            } catch {
                return UIImage(systemName: "video.fill") ?? UIImage()
            }
        }

        private func getVideoDuration(from url: URL) -> TimeInterval {
            let asset = AVAsset(url: url)
            return CMTimeGetSeconds(asset.duration)
        }
    }
}

// MARK: - Image Source Picker

struct ImageSourcePicker: View {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    @Binding var selectedVideoThumbnail: UIImage?
    @Binding var selectedVideoDuration: TimeInterval?
    @Binding var isPresented: Bool

    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo or Video", systemImage: "camera")
                    }
                }

                Button {
                    showPhotosPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
            }
            .navigationTitle("Add Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePickerView(
                    sourceType: .camera,
                    onPhotoPicked: { image in
                        selectedImage = image
                        selectedVideoURL = nil
                        isPresented = false
                    },
                    onVideoPicked: { url, thumbnail, duration in
                        selectedVideoURL = url
                        selectedVideoThumbnail = thumbnail
                        selectedVideoDuration = duration
                        selectedImage = nil
                        isPresented = false
                    }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            // Check if it's an image or video
                            if let image = UIImage(data: data) {
                                selectedImage = image
                                selectedVideoURL = nil
                            } else {
                                // It's a video, save to temp file
                                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                                try? data.write(to: tempURL)
                                selectedVideoURL = tempURL
                                // Generate thumbnail
                                let asset = AVAsset(url: tempURL)
                                if let generator = AVAssetImageGenerator(asset: asset) as? AVAssetImageGenerator {
                                    generator.appliesPreferredTrackTransform = true
                                    generator.maximumSize = CGSize(width: 200, height: 200)
                                    do {
                                        let cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
                                        selectedVideoThumbnail = UIImage(cgImage: cgImage)
                                    } catch {
                                        selectedVideoThumbnail = UIImage(systemName: "video.fill")
                                    }
                                }
                                selectedVideoDuration = CMTimeGetSeconds(asset.duration)
                                selectedImage = nil
                            }
                            isPresented = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var image: UIImage?
    @Previewable @State var videoURL: URL?
    @Previewable @State var thumbnail: UIImage?
    @Previewable @State var duration: TimeInterval?
    @Previewable @State var showPicker = true

    ImageSourcePicker(
        selectedImage: $image,
        selectedVideoURL: $videoURL,
        selectedVideoThumbnail: $thumbnail,
        selectedVideoDuration: $duration,
        isPresented: $showPicker
    )
}
