import CloudKit
import Foundation

// MARK: - Record Type Names

/// CKRecord `recordType` constants for the Space feature's custom-zone hierarchy.
/// See docs/features/space-plan.md §5.
enum SpaceRecordType {
    static let space = "Space"
    static let spaceReflection = "SpaceReflection"
    static let response = "Response"
}

// MARK: - Field Keys

/// CKRecord field-key constants, grouped by the record type that owns them.
enum SpaceRecordField {
    // Space (root record)
    static let name = "name"
    static let detail = "detail"
    static let emoji = "emoji"

    // SpaceReflection (child of Space)
    static let spaceID = "spaceID"
    static let title = "title"
    static let promptText = "promptText"

    // Response (child of SpaceReflection)
    static let reflectionID = "reflectionID"
    static let body = "body"
}

// MARK: - CKRecord <-> Entity Mapping

/// Maps between `CKRecord`s in the Space custom-zone hierarchy and the plain domain
/// entities in `Domain/Entities/Space/`. Field mapping mirrors the plain
/// `record["key"] = value as CKRecordValue` style used by the personal-journal backup
/// service's per-entity upload methods. Author/date come from CloudKit's system
/// metadata (`creatorUserRecordID`, `creationDate`, `modificationDate`) rather than
/// custom fields, so there's nothing to write for those on the way out.
enum SpaceRecordMapper {

    // MARK: Space (root)

    /// Builds a brand-new root `Space` CKRecord inside `zoneID`, ready to be saved
    /// together with its `CKShare` in one atomic `CKModifyRecordsOperation`
    /// (see `SpaceCloudService.createSpace`).
    static func makeSpaceRecord(
        recordName: String = UUID().uuidString,
        zoneID: CKRecordZone.ID,
        name: String,
        detail: String?,
        emoji: String?
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: SpaceRecordType.space, recordID: recordID)
        record[SpaceRecordField.name] = name as CKRecordValue
        if let detail {
            record[SpaceRecordField.detail] = detail as CKRecordValue
        }
        if let emoji {
            record[SpaceRecordField.emoji] = emoji as CKRecordValue
        }
        return record
    }

    /// Maps a fetched root `Space` CKRecord into the domain entity. `lane`, `isOwner`,
    /// and `participantCount` are supplied by the caller because none of them are
    /// derivable from the record alone (lane depends on which database it was fetched
    /// from; participant count requires a separate `CKShare` fetch).
    static func space(
        from record: CKRecord,
        lane: SpaceLane,
        isOwner: Bool,
        participantCount: Int
    ) -> Space? {
        guard record.recordType == SpaceRecordType.space,
              let name = record[SpaceRecordField.name] as? String else {
            return nil
        }

        let zoneRef = SpaceZoneRef(
            zoneName: record.recordID.zoneID.zoneName,
            ownerName: record.recordID.zoneID.ownerName,
            lane: lane
        )

        return Space(
            id: record.recordID.recordName,
            name: name,
            detail: record[SpaceRecordField.detail] as? String,
            emoji: record[SpaceRecordField.emoji] as? String,
            isOwner: isOwner,
            zoneID: zoneRef,
            createdAt: record.creationDate,
            participantCount: participantCount
        )
    }

    // MARK: SpaceReflection / Response mapping helpers

    /// Builds a new `SpaceReflection` CKRecord as a child of the root `Space` record.
    ///
    /// The `parent` reference (action `.none`) is what carries the zone's `CKShare` down
    /// to the child — without it, participants never see the record (plan §3, the classic
    /// CKShare bug). `spaceID` is also stored as a plain field as a belt-and-braces fallback
    /// for the reader.
    static func makeReflectionRecord(
        recordName: String = UUID().uuidString,
        zoneID: CKRecordZone.ID,
        spaceID: String,
        title: String,
        promptText: String
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: SpaceRecordType.spaceReflection, recordID: recordID)
        record[SpaceRecordField.title] = title as CKRecordValue
        record[SpaceRecordField.promptText] = promptText as CKRecordValue
        record[SpaceRecordField.spaceID] = spaceID as CKRecordValue
        let parentID = CKRecord.ID(recordName: spaceID, zoneID: zoneID)
        record.parent = CKRecord.Reference(recordID: parentID, action: .none)
        return record
    }

    /// Builds a new `Response` CKRecord as a child of its `SpaceReflection` record. The
    /// `parent` reference again carries the share down the hierarchy.
    static func makeResponseRecord(
        recordName: String = UUID().uuidString,
        zoneID: CKRecordZone.ID,
        reflectionID: String,
        body: String
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: SpaceRecordType.response, recordID: recordID)
        record[SpaceRecordField.body] = body as CKRecordValue
        record[SpaceRecordField.reflectionID] = reflectionID as CKRecordValue
        let parentID = CKRecord.ID(recordName: reflectionID, zoneID: zoneID)
        record.parent = CKRecord.Reference(recordID: parentID, action: .none)
        return record
    }

    /// Maps a fetched `SpaceReflection` CKRecord into the domain entity.
    static func spaceReflection(from record: CKRecord, isMine: Bool) -> SpaceReflection? {
        guard record.recordType == SpaceRecordType.spaceReflection,
              let title = record[SpaceRecordField.title] as? String,
              let promptText = record[SpaceRecordField.promptText] as? String else {
            return nil
        }

        let spaceID = record.parent?.recordID.recordName
            ?? record[SpaceRecordField.spaceID] as? String
            ?? ""

        return SpaceReflection(
            id: record.recordID.recordName,
            spaceID: spaceID,
            title: title,
            promptText: promptText,
            authorRecordName: record.creatorUserRecordID?.recordName,
            authorDisplayName: nil, // resolved from CKShare.participants by the caller
            createdAt: record.creationDate,
            modifiedAt: record.modificationDate,
            isMine: isMine
        )
    }

    /// Maps a fetched `Response` CKRecord into the domain entity.
    static func spaceResponse(from record: CKRecord, isMine: Bool) -> SpaceResponse? {
        guard record.recordType == SpaceRecordType.response,
              let body = record[SpaceRecordField.body] as? String else {
            return nil
        }

        let reflectionID = record.parent?.recordID.recordName
            ?? record[SpaceRecordField.reflectionID] as? String
            ?? ""

        return SpaceResponse(
            id: record.recordID.recordName,
            reflectionID: reflectionID,
            body: body,
            authorRecordName: record.creatorUserRecordID?.recordName,
            authorDisplayName: nil, // resolved from CKShare.participants by the caller
            createdAt: record.creationDate,
            isMine: isMine
        )
    }
}
