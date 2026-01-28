import Foundation

struct SyncResult {
    let success: Bool
    let itemsSynced: Int
    let errors: [SyncError]
    let completedAt: Date

    var hasErrors: Bool {
        !errors.isEmpty
    }

    var summary: String {
        if success {
            return "Successfully synced \(itemsSynced) items"
        } else {
            return "Sync failed with \(errors.count) errors"
        }
    }
}

enum SyncError: Error, LocalizedError {
    case networkUnavailable
    case iCloudAccountNotFound
    case iCloudAccountRestricted
    case uploadFailed(String)
    case downloadFailed(String)
    case conflictDetected(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is unavailable. Please check your internet connection."
        case .iCloudAccountNotFound:
            return "No iCloud account found. Please sign in to iCloud in Settings."
        case .iCloudAccountRestricted:
            return "iCloud access is restricted. Please check your parental control settings."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .conflictDetected(let message):
            return "Conflict detected: \(message)"
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}

enum CloudAvailability {
    case available
    case noAccount
    case restricted
    case networkUnavailable
    case temporarilyUnavailable

    var isAvailable: Bool {
        self == .available
    }

    var message: String {
        switch self {
        case .available:
            return "iCloud is available"
        case .noAccount:
            return "Please sign in to iCloud"
        case .restricted:
            return "iCloud access is restricted"
        case .networkUnavailable:
            return "No network connection"
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable"
        }
    }
}

enum SyncStatus: Equatable {
    case idle
    case checking
    case syncing(progress: Double)
    case completed(Date)
    case failed(String)

    var isInProgress: Bool {
        switch self {
        case .checking, .syncing:
            return true
        default:
            return false
        }
    }

    var progress: Double? {
        if case .syncing(let progress) = self {
            return progress
        }
        return nil
    }
}

struct CloudDataSummary {
    let learningsCount: Int
    let reflectionsCount: Int
    let imagesCount: Int
    let voiceNotesCount: Int
    let lastBackupDate: Date?

    var totalItems: Int {
        learningsCount + reflectionsCount + imagesCount + voiceNotesCount
    }

    var isEmpty: Bool {
        totalItems == 0
    }
}
