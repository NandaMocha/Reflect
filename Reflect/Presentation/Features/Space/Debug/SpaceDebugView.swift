//
//  SpaceDebugView.swift
//  Reflect
//
//  DEBUG-only spike harness for proving CloudKit sharing works end-to-end across
//  two devices (the Space feature's H2 gate). Talks to `SpaceCloudService`
//  directly — no `DIContainer`, no repository, no cache — so the raw CloudKit
//  behavior is visible with nothing else in the way.
//
//  Everything here is throwaway: T12 owns the real share-sheet integration, T17
//  owns real child-record CRUD. This file must stay entirely inside `#if DEBUG`
//  so Release builds are byte-identical without it.
//

#if DEBUG

import SwiftUI
import CloudKit

// MARK: - SpaceDebugView

struct SpaceDebugView: View {

    // MARK: State

    @State private var log: String = "Ready.\n"
    @State private var selectedSpace: Space?
    @State private var selectedShare: CKShare?
    @State private var isSharingPresented = false

    // MARK: Dependencies
    // Instantiated directly on purpose — this screen bypasses DIContainer entirely.

    private let service = SpaceCloudService()
    private let container = CKContainer(identifier: "iCloud.xyz.nandamochammad.Reflect")
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    // MARK: Body

    var body: some View {
        Form {
            Section("Actions") {
                Button("Check availability") {
                    Task { await checkAvailabilityTapped() }
                }

                Button("Create test space") {
                    Task { await createTestSpace() }
                }

                Button("Share invite") {
                    isSharingPresented = true
                }
                .disabled(selectedShare == nil)

                Button("List owned spaces") {
                    Task { await listOwnedSpaces() }
                }

                Button("List joined spaces") {
                    Task { await listJoinedSpaces() }
                }

                Button("Write probe reflection") {
                    Task { await writeProbeReflection() }
                }
                .disabled(selectedSpace == nil)

                Button("Dump zone records") {
                    Task { await dumpZoneRecords() }
                }
                .disabled(selectedSpace == nil)
            }

            // T26/T29 — incremental-sync state. Zone tokens live in UserDefaults under
            // "spaceZoneToken-<zone>-<owner>"; the last fetch summary is written by
            // SpaceCloudService.fetchChanges (DEBUG builds only).
            Section("Zone sync (T26)") {
                let tokenKeys = UserDefaults.standard.dictionaryRepresentation().keys
                    .filter { $0.hasPrefix("spaceZoneToken-") }
                    .sorted()
                if tokenKeys.isEmpty {
                    Text("No zone tokens saved — next fetch per zone is a full snapshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tokenKeys, id: \.self) { key in
                        Text(key.replacingOccurrences(of: "spaceZoneToken-", with: ""))
                            .font(.caption.monospaced())
                    }
                }

                if let summary = UserDefaults.standard.string(forKey: "spaceDebugLastZoneFetch") {
                    Text("Last fetch: \(summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear all zone tokens (force full refetch)", role: .destructive) {
                    let keys = UserDefaults.standard.dictionaryRepresentation().keys
                        .filter { $0.hasPrefix("spaceZoneToken-") }
                    for key in keys {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                    appendLog("Cleared \(keys.count) zone token(s).\n")
                }
            }

            if let space = selectedSpace {
                Section("Selected space") {
                    Text(space.name)
                    Text(space.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("zone: \(space.zoneID.zoneName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("lane: \(space.zoneID.lane == .privateDB ? "private" : "shared")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Log") {
                ScrollView {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 300)

                Button("Clear log") {
                    log = ""
                }
            }
        }
        .navigationTitle("Space Debug (spike)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isSharingPresented) {
            if let share = selectedShare {
                CloudSharingControllerRepresentable(share: share, container: container, onLog: appendLog)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spaceShareInviteReceived)) { notification in
            guard let metadata = notification.object as? CKShare.Metadata else {
                appendLog("spaceShareInviteReceived fired without CKShare.Metadata payload")
                return
            }
            Task { await acceptInvite(metadata: metadata) }
        }
    }

    // MARK: - Actions

    private func checkAvailabilityTapped() async {
        let availability = await service.checkAvailability()
        appendLog("Availability: \(availability.message)")
    }

    private func createTestSpace() async {
        appendLog("Creating test space…")
        do {
            let (space, share) = try await service.createSpace(
                name: "Spike \(shortDateString)",
                detail: nil,
                emoji: "🧪"
            )
            selectedSpace = space
            selectedShare = share
            appendLog("Created space '\(space.name)' id=\(space.id) zone=\(space.zoneID.zoneName)")
        } catch {
            appendLog("Create space failed: \(error.localizedDescription)")
        }
    }

    private func listOwnedSpaces() async {
        appendLog("Fetching owned spaces…")
        do {
            let spaces = try await service.fetchOwnedSpaces()
            if spaces.isEmpty {
                appendLog("No owned spaces.")
            } else {
                for space in spaces {
                    appendLog("Owned: '\(space.name)' id=\(space.id) zone=\(space.zoneID.zoneName) participants=\(space.participantCount)")
                }
            }
        } catch {
            appendLog("Fetch owned spaces failed: \(error.localizedDescription)")
        }
    }

    private func listJoinedSpaces() async {
        appendLog("Fetching joined spaces…")
        do {
            let spaces = try await service.fetchJoinedSpaces()
            if spaces.isEmpty {
                appendLog("No joined spaces.")
            } else {
                for space in spaces {
                    appendLog("Joined: '\(space.name)' id=\(space.id) zone=\(space.zoneID.zoneName) owner=\(space.zoneID.ownerName) participants=\(space.participantCount)")
                }
            }
        } catch {
            appendLog("Fetch joined spaces failed: \(error.localizedDescription)")
        }
    }

    /// Throwaway inline `CKRecord` save — T17 owns real `SpaceReflection` CRUD.
    private func writeProbeReflection() async {
        guard let space = selectedSpace else {
            appendLog("No selected space — create or join one first.")
            return
        }
        appendLog("Writing probe reflection into '\(space.name)'…")
        do {
            let zoneID = CKRecordZone.ID(zoneName: space.zoneID.zoneName, ownerName: space.zoneID.ownerName)
            let parentRecordID = CKRecord.ID(recordName: space.id, zoneID: zoneID)
            let childRecordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)

            let record = CKRecord(recordType: SpaceRecordType.spaceReflection, recordID: childRecordID)
            record.parent = CKRecord.Reference(recordID: parentRecordID, action: .none)
            record[SpaceRecordField.spaceID] = space.id as CKRecordValue
            record[SpaceRecordField.title] = "Spike probe" as CKRecordValue
            record[SpaceRecordField.promptText] = "Probe written at \(shortDateString)" as CKRecordValue

            let saved = try await database(for: space.zoneID.lane).save(record)
            appendLog("Saved probe reflection \(saved.recordID.recordName)")
        } catch {
            appendLog("Write probe failed: \(error.localizedDescription)")
        }
    }

    private func dumpZoneRecords() async {
        guard let space = selectedSpace else {
            appendLog("No selected space — create or join one first.")
            return
        }
        appendLog("Dumping zone records for '\(space.name)'…")

        let zoneID = CKRecordZone.ID(zoneName: space.zoneID.zoneName, ownerName: space.zoneID.ownerName)
        let database = database(for: space.zoneID.lane)
        let recordTypes = [SpaceRecordType.space, SpaceRecordType.spaceReflection, SpaceRecordType.response]

        for recordType in recordTypes {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let results = try await database.records(matching: query, inZoneWith: zoneID)
                for (recordID, result) in results.matchResults {
                    switch result {
                    case .success(let record):
                        appendLog("[\(recordType)] \(recordID.recordName) modified=\(record.modificationDate?.description ?? "-")")
                    case .failure(let error):
                        appendLog("[\(recordType)] \(recordID.recordName) fetch error: \(error.localizedDescription)")
                    }
                }
            } catch {
                appendLog("Query \(recordType) failed: \(error.localizedDescription)")
            }
        }
    }

    private func acceptInvite(metadata: CKShare.Metadata) async {
        appendLog("Accepting share invite…")
        do {
            let space = try await service.acceptShare(metadata: metadata)
            selectedSpace = space
            appendLog("Joined space '\(space.name)' id=\(space.id) zone=\(space.zoneID.zoneName) owner=\(space.zoneID.ownerName)")
        } catch {
            appendLog("Accept share failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func database(for lane: SpaceLane) -> CKDatabase {
        switch lane {
        case .privateDB: return privateDB
        case .sharedDB: return sharedDB
        }
    }

    private var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func appendLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        log += "[\(formatter.string(from: Date()))] \(text)\n"
    }
}

// MARK: - UICloudSharingController wrapper
//
// Minimal throwaway wrapper — do NOT depend on this from anywhere else. T12 owns
// the real share-sheet integration.

private struct CloudSharingControllerRepresentable: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onLog: (String) -> Void

    func makeCoordinator() -> SpaceDebugSharingDelegate {
        let delegate = SpaceDebugSharingDelegate()
        delegate.onLog = onLog
        return delegate
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No-op: the share/container pair is fixed for the lifetime of this sheet.
    }
}

private final class SpaceDebugSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    var onLog: ((String) -> Void)?

    func itemTitle(for csc: UICloudSharingController) -> String? {
        csc.share?[CKShare.SystemFieldKey.title] as? String
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        onLog?("Share save failed: \(error.localizedDescription)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        onLog?("Share saved.")
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        onLog?("Sharing stopped.")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SpaceDebugView()
    }
}

#endif
