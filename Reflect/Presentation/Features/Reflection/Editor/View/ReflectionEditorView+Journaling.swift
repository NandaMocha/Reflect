import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
import OSLog
import CoreLocation

// MARK: - Captured Location Model

struct CapturedLocation {
    let latitude: Double
    let longitude: Double
    let name: String?
}

// MARK: - Journaling Suggestions Extension

#if canImport(JournalingSuggestions)
extension ReflectionEditorView {

    // MARK: - Handle Journaling Suggestion

    @MainActor
    func handleJournalingSuggestion(_ item: JournalingSuggestion) {
        os_log("🌟 [JOURNALING] Processing suggestion: %@", log: .default, type: .info, item.title)

        // Add title if available
        if !item.title.isEmpty {
            if !content.isEmpty {
                content += "\n\n"
            }
            content += item.title
            hasChanges = true
        }

        // Update date from DateInterval
        if let dateInterval = item.date {
            selectedDate = dateInterval.start
            hasChanges = true
            os_log("📅 [JOURNALING] Updated date to: %@", log: .default, type: .info, dateInterval.start.formatted())
        }

        // Extract location data and photos
        Task {
            await extractLocation(from: item)
            await extractPhotos(from: item)
        }

        HapticManager.shared.lightImpact()
    }

    // MARK: - Extract Location

    @MainActor
    private func extractLocation(from item: JournalingSuggestion) async {
        do {
            let locations = await item.content(forType: JournalingSuggestion.Location.self)

            guard let location = locations.first else {
                os_log("📍 [JOURNALING] No location in suggestion", log: .default, type: .info)
                return
            }

            // Capture location coordinates
            if let coordinate = location.location?.coordinate {
                capturedLocation = CapturedLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    name: location.place ?? location.city
                )
                os_log("📍 [JOURNALING] Captured location: %@", log: .default, type: .info, location.place ?? location.city ?? "\(coordinate.latitude), \(coordinate.longitude)")
            }

            // Add location info to content
            var locationParts: [String] = []
            if let place = location.place, !place.isEmpty {
                locationParts.append("📍 \(place)")
            }
            if let city = location.city, !city.isEmpty {
                locationParts.append(city)
            }

            if !locationParts.isEmpty {
                if !content.isEmpty && !content.hasSuffix(" ") {
                    content += "\n\n"
                }
                content += locationParts.joined(separator: ", ")
                hasChanges = true
            }

        } catch {
            os_log("⚠️ [JOURNALING] Failed to extract location: %@", log: .default, type: .error, error.localizedDescription)
        }
    }

    // MARK: - Extract Photos

    @MainActor
    private func extractPhotos(from item: JournalingSuggestion) async {
        let photos = await item.content(forType: JournalingSuggestion.Photo.self)

        os_log("📷 [JOURNALING] Found %d photos", log: .default, type: .info, photos.count)

        for photo in photos {
            // photo.photo is a URL - load image from file URL
            let imageURL = photo.photo
            await loadImage(from: imageURL)
        }
    }

    private func loadImage(from url: URL) async {
        do {
            // Load image from file URL
            let data = try Data(contentsOf: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    let input = ImageInput(image: image)
                    images.append(input)
                    hasChanges = true
                    os_log("📷 [JOURNALING] Loaded photo", log: .default, type: .info)
                }
            } else {
                await MainActor.run {
                    showError(message: "Failed to process the selected photo.")
                }
            }
        } catch {
            os_log("⚠️ [JOURNALING] Failed to load photo from URL: %@", log: .default, type: .error, error.localizedDescription)
            await MainActor.run {
                showError(message: "Failed to load photo: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Show Error Alert

    private func showError(message: String) {
        errorMessage = message
        showErrorAlert = true
        HapticManager.shared.error()
    }
}
#endif
