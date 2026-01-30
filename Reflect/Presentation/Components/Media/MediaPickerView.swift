import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Media Type

enum MediaType: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"

    var icon: String {
        switch self {
        case .photo: return "camera"
        case .video: return "video"
        }
    }
}

// MARK: - Media Result

struct MediaResult {
    let image: UIImage?
    let videoURL: URL?
    let videoThumbnail: UIImage?
    let videoDuration: TimeInterval?
    let type: MediaType

    var isPhoto: Bool { type == .photo }
    var isVideo: Bool { type == .video }

    init(image: UIImage?, videoURL: URL? = nil, videoThumbnail: UIImage? = nil, videoDuration: TimeInterval? = nil, type: MediaType) {
        self.image = image
        self.videoURL = videoURL
        self.videoThumbnail = videoThumbnail
        self.videoDuration = videoDuration
        self.type = type
    }
}

// MARK: - Media Picker View

struct MediaPickerView: UIViewControllerRepresentable {
    let mediaType: MediaType
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedMedia: MediaResult?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false

        // Set media type
        switch mediaType {
        case .photo:
            picker.mediaTypes = ["public.image"]
        case .video:
            picker.mediaTypes = ["public.movie"]
            picker.videoMaximumDuration = 60 // 60 seconds max
            picker.videoQuality = .typeHigh
        }

        // Mirror camera for front-facing (selfie) orientation
        if sourceType == .camera {
            picker.cameraDevice = .front
            picker.cameraCaptureMode = mediaType == .video ? .video : .photo
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MediaPickerView

        init(_ parent: MediaPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Mirror the image for front camera
                let mirroredImage = mirrorImage(image)
                parent.selectedMedia = MediaResult(image: mirroredImage, type: parent.mediaType)
            } else if let mediaURL = info[.mediaURL] as? URL {
                // Generate thumbnail and get duration for video
                let thumbnail = generateVideoThumbnail(from: mediaURL)
                let duration = getVideoDuration(from: mediaURL)
                parent.selectedMedia = MediaResult(
                    image: nil,
                    videoURL: mediaURL,
                    videoThumbnail: thumbnail,
                    videoDuration: duration,
                    type: parent.mediaType
                )
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

// MARK: - Media Source Picker

struct MediaSourcePicker: View {
    @Binding var selectedImage: UIImage?
    @Binding var selectedVideoURL: URL?
    @Binding var isPresented: Bool

    @State private var selectedMediaType: MediaType = .photo
    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedVideoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                // Media Type Picker
                Section {
                    Picker("Media Type", selection: $selectedMediaType) {
                        ForEach(MediaType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Source Options
                Section {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label(selectedMediaType == .photo ? "Take Photo" : "Record Video",
                                  systemImage: selectedMediaType.icon)
                        }
                    }

                    Button {
                        selectedMediaType == .photo ? (showPhotosPicker = true) : (showPhotosPicker = true)
                    } label: {
                        Label(selectedMediaType == .photo ? "Choose Photo from Library" : "Choose Video from Library",
                              systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("Source")
                }
            }
            .navigationTitle(selectedMediaType == .photo ? "Add Photo" : "Add Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                MediaPickerView(
                    mediaType: selectedMediaType,
                    sourceType: .camera,
                    selectedMedia: Binding(
                        get: {
                            if let image = selectedImage {
                                return MediaResult(image: image, type: .photo)
                            } else if let videoURL = selectedVideoURL {
                                return MediaResult(image: nil, videoURL: videoURL, type: .video)
                            }
                            return nil
                        },
                        set: { media in
                            if let media = media {
                                selectedImage = media.image
                                selectedVideoURL = media.videoURL
                                isPresented = false
                            }
                        }
                    )
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: selectedMediaType == .photo ? $selectedPhotoItem : $selectedVideoItem)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedImage = image
                            isPresented = false
                        }
                    }
                }
            }
            .onChange(of: selectedVideoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            // Save video data to temporary file
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                            try? data.write(to: tempURL)
                            selectedVideoURL = tempURL
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
    @Previewable @State var showPicker = true

    MediaSourcePicker(
        selectedImage: $image,
        selectedVideoURL: $videoURL,
        isPresented: $showPicker
    )
}
