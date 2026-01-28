import SwiftUI
import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Image Source Picker

struct ImageSourcePicker: View {
    @Binding var selectedImage: UIImage?
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
                        Label("Take Photo", systemImage: "camera")
                    }
                }

                Button {
                    showPhotosPicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                }
            }
            .navigationTitle("Add Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera, selectedImage: $selectedImage)
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem)
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
            .onChange(of: selectedImage) { _, newImage in
                if newImage != nil {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var image: UIImage?
    @Previewable @State var showPicker = true

    ImageSourcePicker(selectedImage: $image, isPresented: $showPicker)
}
