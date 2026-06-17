import Foundation
import SwiftData

// Bridges the backend's generic sync rows to the local SwiftData `@Model`s and
// back, mirroring `api/src/sync/entities.ts` (push) and `pull-entities.ts`
// (pull). Everything is `nonisolated` so the `@ModelActor` `SyncActor` can drive
// it off the main actor.
//
// Pull: upsert by shared id, resolve relationships by id, set tombstones, keep
// the server `updatedAt`, mark `.synced` — but skip rows the user changed offline
// (Last-Write-Wins by `updatedAt`). Push: project each dirty model into the
// payload columns the backend's `columns` mapper expects.

// MARK: - Model protocols

/// Every cloud-replicated model: shared id + sync metadata + an id predicate so
/// the mapper can find-or-create generically.
nonisolated protocol SyncModel: PersistentModel {
    var id: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncStatus: SyncStatus { get set }
    static func idPredicate(_ id: UUID) -> Predicate<Self>
}

/// A model the client may push (create/update/delete). Pull-only entities
/// (organization, member, notification) are `SyncModel` but not `SyncPushable`.
nonisolated protocol SyncPushable: SyncModel {
    static var syncEntity: String { get }
    /// Owning org id. Taxonomy rows with no on-device org link fall back to
    /// `activeOrg`; an unresolvable row returns nil and is skipped.
    func syncOrganizationID(activeOrg: UUID) -> UUID?
    func syncPayload() -> SyncRow
}

// MARK: - JSON payload builders

/// Builds `JSONValue`s for push payloads (the inverse of the `SyncRow` readers).
nonisolated enum SyncJSON {
    static func uuid(_ value: UUID?) -> JSONValue { value.map { .string($0.uuidString) } ?? .null }
    static func double(_ value: Double) -> JSONValue { .number(value) }
    static func double(_ value: Double?) -> JSONValue { value.map { .number($0) } ?? .null }
    static func date(_ value: Date) -> JSONValue { .string(JSONCoding.iso(value)) }
    static func date(_ value: Date?) -> JSONValue { value.map { .string(JSONCoding.iso($0)) } ?? .null }
    static func uuids(_ values: [UUID]) -> JSONValue { .array(values.map { .string($0.uuidString) }) }
    static func strings(_ values: [String]) -> JSONValue { .array(values.map { .string($0) }) }
    static func optString(_ value: String?) -> JSONValue { value.map { .string($0) } ?? .null }

    /// A SwiftData blob column → nested JSON (or `null`).
    static func blob(_ data: Data?) -> JSONValue {
        guard let data, let value = JSONValue(data: data) else { return .null }
        return value
    }

    /// `Report.photoNotes` → `{ "<uuid>": "<note>" }`.
    static func noteMap(_ map: [UUID: String]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, JSONValue.string($0.value)) }))
    }
}

// MARK: - Pull dispatch

nonisolated enum SyncMappers {
    /// Apply order: parents before children so relationships resolve by id.
    static let pullOrder = [
        "organization", "projectLabel", "tag", "project", "member",
        "checklistTemplate", "photo", "task", "checklist", "checklistItem",
        "photoComment", "taskComment", "report", "beforeAfterPair", "page",
        "measurement", "notification",
    ]

    static func applyChanges(_ changes: [String: [SyncRow]], in ctx: ModelContext) {
        for entity in pullOrder {
            guard let rows = changes[entity] else { continue }
            for row in rows { apply(entity: entity, row: row, in: ctx, lww: true) }
        }
    }

    /// `lww`: a normal pull defers to newer unsynced local edits; a `stale` push
    /// ack (`lww == false`) always overwrites — the server row is the LWW winner.
    static func apply(entity: String, row: SyncRow, in ctx: ModelContext, lww: Bool) {
        switch entity {
        case "organization": upsertOrganization(row, in: ctx, lww: lww)
        case "member": upsertMember(row, in: ctx, lww: lww)
        case "projectLabel": upsertProjectLabel(row, in: ctx, lww: lww)
        case "tag": upsertTag(row, in: ctx, lww: lww)
        case "project": upsertProject(row, in: ctx, lww: lww)
        case "photo": upsertPhoto(row, in: ctx, lww: lww)
        case "photoComment": upsertPhotoComment(row, in: ctx, lww: lww)
        case "task": upsertTask(row, in: ctx, lww: lww)
        case "taskComment": upsertTaskComment(row, in: ctx, lww: lww)
        case "checklist": upsertChecklist(row, in: ctx, lww: lww)
        case "checklistItem": upsertChecklistItem(row, in: ctx, lww: lww)
        case "checklistTemplate": upsertChecklistTemplate(row, in: ctx, lww: lww)
        case "report": upsertReport(row, in: ctx, lww: lww)
        case "beforeAfterPair": upsertBeforeAfterPair(row, in: ctx, lww: lww)
        case "page": upsertPage(row, in: ctx, lww: lww)
        case "measurement": upsertMeasurement(row, in: ctx, lww: lww)
        case "notification": upsertNotification(row, in: ctx, lww: lww)
        default: break
        }
    }

    // MARK: Outbox ack reconciliation

    /// Flips a pushed row to `.synced` unless a newer local edit arrived during
    /// the in-flight push (`updatedAt` now exceeds what we sent). `force` accepts
    /// the server's verdict for a rejected mutation so it stops re-pushing.
    static func markResolved(entity: String, id: UUID, pushedMs: Int?, force: Bool, in ctx: ModelContext) {
        func flip<T: SyncModel>(_ type: T.Type) {
            guard let row = find(type, id, in: ctx) else { return }
            if force || pushedMs == nil || ms(row.updatedAt) <= pushedMs! {
                row.syncStatus = .synced
            }
        }
        switch entity {
        case "projectLabel": flip(ProjectLabel.self)
        case "tag": flip(Tag.self)
        case "project": flip(Project.self)
        case "photo": flip(Photo.self)
        case "photoComment": flip(PhotoComment.self)
        case "task": flip(ProjectTask.self)
        case "taskComment": flip(TaskComment.self)
        case "checklist": flip(Checklist.self)
        case "checklistItem": flip(ChecklistItem.self)
        case "checklistTemplate": flip(ChecklistTemplate.self)
        case "report": flip(Report.self)
        case "beforeAfterPair": flip(BeforeAfterPair.self)
        case "page": flip(Page.self)
        case "measurement": flip(Measurement.self)
        default: break
        }
    }

    // MARK: - Generic find / upsert

    static func find<T: SyncModel>(_ type: T.Type, _ id: UUID?, in ctx: ModelContext) -> T? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<T>(predicate: T.idPredicate(id))
        descriptor.fetchLimit = 1
        return (try? ctx.fetch(descriptor))?.first
    }

    /// Find-or-create by id, run the LWW guard, set the per-entity fields via
    /// `apply`, then stamp the shared metadata and mark `.synced`.
    private static func upsert<T: SyncModel>(
        _ type: T.Type,
        _ row: SyncRow,
        in ctx: ModelContext,
        lww: Bool,
        make: () -> T,
        apply: (T) -> Void
    ) {
        guard let id = row.uuid("id") else { return }
        let updated = row.date("updatedAt") ?? .now
        let existing = find(type, id, in: ctx)
        if lww, let existing, existing.syncStatus != .synced, ms(existing.updatedAt) > ms(updated) {
            return // a newer offline edit wins; it will push on the next cycle
        }
        let model = existing ?? {
            let created = make()
            ctx.insert(created)
            return created
        }()
        model.id = id
        apply(model)
        model.createdAt = row.date("createdAt") ?? model.createdAt
        model.updatedAt = updated
        model.deletedAt = row.date("deletedAt")
        model.syncStatus = .synced
    }

    private static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    // MARK: - Per-entity pull upserts

    private static func upsertOrganization(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Organization.self, row, in: ctx, lww: lww,
               make: { Organization(name: "", ownerAccountID: row.uuid("ownerAccountId") ?? UUID()) }) { org in
            org.name = row.string("name") ?? org.name
            org.logoFileName = row.string("logoFileName")
            org.phone = row.string("phone") ?? ""
            org.email = row.string("email") ?? ""
            org.website = row.string("website") ?? ""
            org.ownerAccountID = row.uuid("ownerAccountId") ?? org.ownerAccountID
            org.planTier = PlanTier(rawValue: row.string("planTier") ?? "") ?? .basic
            org.storageAddOn = StorageAddOn(rawValue: row.string("storageAddOn") ?? "") ?? .none
            org.trialStartedAt = row.date("trialStartedAt")
            org.subscriptionStartedAt = row.date("subscriptionStartedAt")
        }
    }

    private static func upsertMember(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(OrgMember.self, row, in: ctx, lww: lww,
               make: { OrgMember(name: "", phoneNumber: "") }) { member in
            member.name = row.string("name") ?? member.name
            member.phoneNumber = row.string("phoneNumber") ?? ""
            member.title = row.string("title") ?? ""
            member.role = OrgMember.Role(rawValue: row.string("role") ?? "") ?? .standard
            member.status = OrgMember.Status(rawValue: row.string("status") ?? "") ?? .invited
            member.colorHex = row.string("colorHex") ?? member.colorHex
            member.accountID = row.uuid("accountId")
            member.inviteCode = row.string("inviteCode")
            member.inviteCreatedAt = row.date("inviteCreatedAt")
            member.organization = find(Organization.self, row.uuid("organizationId"), in: ctx)
            member.projects = row.uuids("projectIds").compactMap { find(Project.self, $0, in: ctx) }
        }
    }

    private static func upsertProjectLabel(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(ProjectLabel.self, row, in: ctx, lww: lww,
               make: { ProjectLabel(name: "", colorHex: "#1B98E0") }) { label in
            label.name = row.string("name") ?? label.name
            label.colorHex = row.string("colorHex") ?? label.colorHex
            label.sortOrder = row.int("sortOrder") ?? 0
        }
    }

    private static func upsertTag(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Tag.self, row, in: ctx, lww: lww,
               make: { Tag(name: "", colorHex: "#13B5B1") }) { tag in
            tag.name = row.string("name") ?? tag.name
            tag.colorHex = row.string("colorHex") ?? tag.colorHex
        }
    }

    private static func upsertProject(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Project.self, row, in: ctx, lww: lww, make: { Project(name: "") }) { project in
            project.name = row.string("name") ?? project.name
            project.address = row.string("address") ?? ""
            project.latitude = row.double("latitude")
            project.longitude = row.double("longitude")
            project.notes = row.string("notes") ?? ""
            project.coverPhotoID = row.uuid("coverPhotoId")
            project.label = find(ProjectLabel.self, row.uuid("labelId"), in: ctx)
            project.organization = find(Organization.self, row.uuid("organizationId"), in: ctx)
        }
    }

    private static func upsertPhoto(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Photo.self, row, in: ctx, lww: lww,
               make: { Photo(fileName: "", thumbnailFileName: "") }) { photo in
            photo.project = find(Project.self, row.uuid("projectId"), in: ctx)
            photo.author = find(OrgMember.self, row.uuid("authorMemberId"), in: ctx)
            photo.capturedAt = row.date("capturedAt") ?? photo.capturedAt
            photo.latitude = row.double("latitude")
            photo.longitude = row.double("longitude")
            photo.fileName = row.string("fileName") ?? ""
            photo.thumbnailFileName = row.string("thumbnailFileName") ?? ""
            photo.caption = row.string("caption") ?? ""
            photo.annotationData = row.jsonData("annotationData")
            photo.source = Photo.Source(rawValue: row.string("source") ?? "") ?? .camera
            photo.mediaType = Photo.MediaType(rawValue: row.string("mediaType") ?? "") ?? .photo
            photo.durationSeconds = row.double("durationSeconds")
            photo.tags = row.uuids("tagIds").compactMap { find(Tag.self, $0, in: ctx) }
            // Server-owned media-pipeline state (Phase 3); client never pushes it.
            photo.processingStatus = Photo.ProcessingStatus(rawValue: row.string("processingStatus") ?? "") ?? .done
        }
    }

    private static func upsertPhotoComment(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(PhotoComment.self, row, in: ctx, lww: lww, make: { PhotoComment(text: "") }) { comment in
            comment.text = row.string("text") ?? ""
            comment.mentionIDs = row.uuids("mentionIds")
            comment.author = find(OrgMember.self, row.uuid("authorMemberId"), in: ctx)
            comment.photo = find(Photo.self, row.uuid("photoId"), in: ctx)
        }
    }

    private static func upsertTask(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(ProjectTask.self, row, in: ctx, lww: lww, make: { ProjectTask(title: "") }) { task in
            task.title = row.string("title") ?? task.title
            task.note = row.string("note") ?? ""
            task.dueDate = row.date("dueDate")
            task.completedAt = row.date("completedAt")
            task.attachedPhotoIDs = row.uuids("attachedPhotoIds")
            task.project = find(Project.self, row.uuid("projectId"), in: ctx)
            task.assignee = find(OrgMember.self, row.uuid("assigneeMemberId"), in: ctx)
        }
    }

    private static func upsertTaskComment(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(TaskComment.self, row, in: ctx, lww: lww, make: { TaskComment(text: "") }) { comment in
            comment.text = row.string("text") ?? ""
            comment.mentionIDs = row.uuids("mentionIds")
            comment.author = find(OrgMember.self, row.uuid("authorMemberId"), in: ctx)
            comment.task = find(ProjectTask.self, row.uuid("taskId"), in: ctx)
        }
    }

    private static func upsertChecklist(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Checklist.self, row, in: ctx, lww: lww, make: { Checklist(name: "") }) { checklist in
            checklist.name = row.string("name") ?? checklist.name
            checklist.templateID = row.uuid("templateId")
            checklist.project = find(Project.self, row.uuid("projectId"), in: ctx)
            checklist.assignee = find(OrgMember.self, row.uuid("assigneeMemberId"), in: ctx)
        }
    }

    private static func upsertChecklistItem(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(ChecklistItem.self, row, in: ctx, lww: lww,
               make: { ChecklistItem(title: "", sortOrder: 0) }) { item in
            item.title = row.string("title") ?? item.title
            item.isDone = row.bool("isDone") ?? false
            item.completedAt = row.date("completedAt")
            item.photoID = row.uuid("photoId")
            item.sortOrder = row.int("sortOrder") ?? 0
            item.checklist = find(Checklist.self, row.uuid("checklistId"), in: ctx)
        }
    }

    private static func upsertChecklistTemplate(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(ChecklistTemplate.self, row, in: ctx, lww: lww,
               make: { ChecklistTemplate(name: "") }) { template in
            template.name = row.string("name") ?? template.name
            template.itemTitles = row.strings("itemTitles")
        }
    }

    private static func upsertReport(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Report.self, row, in: ctx, lww: lww, make: { Report(title: "") }) { report in
            report.title = row.string("title") ?? report.title
            report.photoIDs = row.uuids("photoIds")
            report.photoNotes = row.uuidStringMap("photoNotes")
            report.layout = Report.Layout(rawValue: row.string("layout") ?? "") ?? .onePerPage
            report.includesChecklistSummary = row.bool("includesChecklistSummary") ?? false
            report.pdfFileName = row.string("pdfFileName")
            report.project = find(Project.self, row.uuid("projectId"), in: ctx)
        }
    }

    private static func upsertBeforeAfterPair(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(BeforeAfterPair.self, row, in: ctx, lww: lww,
               make: { BeforeAfterPair(beforePhotoID: UUID(), afterPhotoID: UUID()) }) { pair in
            pair.beforePhotoID = row.uuid("beforePhotoId") ?? pair.beforePhotoID
            pair.afterPhotoID = row.uuid("afterPhotoId") ?? pair.afterPhotoID
            pair.layout = BeforeAfterPair.Layout(rawValue: row.string("layout") ?? "") ?? .sideBySide
            pair.project = find(Project.self, row.uuid("projectId"), in: ctx)
        }
    }

    private static func upsertPage(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Page.self, row, in: ctx, lww: lww, make: { Page(title: "") }) { page in
            page.title = row.string("title") ?? page.title
            page.contentData = row.jsonData("contentData") ?? page.contentData
            page.sortOrder = row.int("sortOrder") ?? 0
            page.pdfFileName = row.string("pdfFileName")
            page.project = find(Project.self, row.uuid("projectId"), in: ctx)
            page.author = find(OrgMember.self, row.uuid("authorMemberId"), in: ctx)
        }
    }

    private static func upsertMeasurement(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(Measurement.self, row, in: ctx, lww: lww,
               make: { Measurement(segments: [], unit: .meters) }) { measurement in
            measurement.capturedAt = row.date("capturedAt") ?? measurement.capturedAt
            measurement.unit = Measurement.Unit(rawValue: row.string("unit") ?? "") ?? .meters
            measurement.segmentsData = row.jsonData("segmentsData") ?? measurement.segmentsData
            measurement.totalMeters = row.double("totalMeters") ?? 0
            measurement.snapshotPhotoID = row.uuid("snapshotPhotoId")
            measurement.notes = row.string("notes") ?? ""
            measurement.project = find(Project.self, row.uuid("projectId"), in: ctx)
        }
    }

    private static func upsertNotification(_ row: SyncRow, in ctx: ModelContext, lww: Bool) {
        upsert(AppNotification.self, row, in: ctx, lww: lww,
               make: { AppNotification(kind: .comment, recipient: nil) }) { note in
            note.kind = AppNotification.Kind(rawValue: row.string("kind") ?? "") ?? .comment
            note.bodySnippet = row.string("bodySnippet") ?? ""
            note.isRead = row.bool("isRead") ?? false
            note.readAt = row.date("readAt")
            note.recipient = find(OrgMember.self, row.uuid("recipientMemberId"), in: ctx)
            note.actor = find(OrgMember.self, row.uuid("actorMemberId"), in: ctx)
            note.task = find(ProjectTask.self, row.uuid("taskId"), in: ctx)
            note.checklist = find(Checklist.self, row.uuid("checklistId"), in: ctx)
            note.photo = find(Photo.self, row.uuid("photoId"), in: ctx)
            note.project = find(Project.self, row.uuid("projectId"), in: ctx)
        }
    }
}

// MARK: - SyncModel conformances (id predicate)

extension Organization: SyncModel {
    static func idPredicate(_ id: UUID) -> Predicate<Organization> { #Predicate { $0.id == id } }
}
extension OrgMember: SyncModel {
    static func idPredicate(_ id: UUID) -> Predicate<OrgMember> { #Predicate { $0.id == id } }
}
extension AppNotification: SyncModel {
    static func idPredicate(_ id: UUID) -> Predicate<AppNotification> { #Predicate { $0.id == id } }
}

// MARK: - SyncPushable conformances (entity key, org resolver, payload)

extension ProjectLabel: SyncPushable {
    static var syncEntity: String { "projectLabel" }
    static func idPredicate(_ id: UUID) -> Predicate<ProjectLabel> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { activeOrg }
    func syncPayload() -> SyncRow {
        ["name": .string(name), "colorHex": .string(colorHex), "sortOrder": .int(sortOrder)]
    }
}

extension Tag: SyncPushable {
    static var syncEntity: String { "tag" }
    static func idPredicate(_ id: UUID) -> Predicate<Tag> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { activeOrg }
    func syncPayload() -> SyncRow {
        ["name": .string(name), "colorHex": .string(colorHex)]
    }
}

extension ChecklistTemplate: SyncPushable {
    static var syncEntity: String { "checklistTemplate" }
    static func idPredicate(_ id: UUID) -> Predicate<ChecklistTemplate> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { activeOrg }
    func syncPayload() -> SyncRow {
        ["name": .string(name), "itemTitles": SyncJSON.strings(itemTitles)]
    }
}

extension Project: SyncPushable {
    static var syncEntity: String { "project" }
    static func idPredicate(_ id: UUID) -> Predicate<Project> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { organization?.id }
    func syncPayload() -> SyncRow {
        [
            "name": .string(name),
            "address": .string(address),
            "latitude": SyncJSON.double(latitude),
            "longitude": SyncJSON.double(longitude),
            "notes": .string(notes),
            "coverPhotoId": SyncJSON.uuid(coverPhotoID),
            "labelId": SyncJSON.uuid(label?.id),
        ]
    }
}

extension Photo: SyncPushable {
    static var syncEntity: String { "photo" }
    static func idPredicate(_ id: UUID) -> Predicate<Photo> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "authorMemberId": SyncJSON.uuid(author?.id),
            "capturedAt": SyncJSON.date(capturedAt),
            "latitude": SyncJSON.double(latitude),
            "longitude": SyncJSON.double(longitude),
            "fileName": .string(fileName),
            "thumbnailFileName": .string(thumbnailFileName),
            "caption": .string(caption),
            "annotationData": SyncJSON.blob(annotationData),
            "source": .string(source.rawValue),
            "mediaType": .string(mediaType.rawValue),
            "durationSeconds": SyncJSON.double(durationSeconds),
            "tagIds": SyncJSON.uuids(tags.map(\.id)),
        ]
    }
}

extension PhotoComment: SyncPushable {
    static var syncEntity: String { "photoComment" }
    static func idPredicate(_ id: UUID) -> Predicate<PhotoComment> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { photo?.project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "photoId": SyncJSON.uuid(photo?.id),
            "authorMemberId": SyncJSON.uuid(author?.id),
            "text": .string(text),
            "mentionIds": SyncJSON.uuids(mentionIDs),
        ]
    }
}

extension ProjectTask: SyncPushable {
    static var syncEntity: String { "task" }
    static func idPredicate(_ id: UUID) -> Predicate<ProjectTask> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "assigneeMemberId": SyncJSON.uuid(assignee?.id),
            "title": .string(title),
            "note": .string(note),
            "dueDate": SyncJSON.date(dueDate),
            "completedAt": SyncJSON.date(completedAt),
            "attachedPhotoIds": SyncJSON.uuids(attachedPhotoIDs),
        ]
    }
}

extension TaskComment: SyncPushable {
    static var syncEntity: String { "taskComment" }
    static func idPredicate(_ id: UUID) -> Predicate<TaskComment> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { task?.project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "taskId": SyncJSON.uuid(task?.id),
            "authorMemberId": SyncJSON.uuid(author?.id),
            "text": .string(text),
            "mentionIds": SyncJSON.uuids(mentionIDs),
        ]
    }
}

extension Checklist: SyncPushable {
    static var syncEntity: String { "checklist" }
    static func idPredicate(_ id: UUID) -> Predicate<Checklist> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "assigneeMemberId": SyncJSON.uuid(assignee?.id),
            "name": .string(name),
            "templateId": SyncJSON.uuid(templateID),
        ]
    }
}

extension ChecklistItem: SyncPushable {
    static var syncEntity: String { "checklistItem" }
    static func idPredicate(_ id: UUID) -> Predicate<ChecklistItem> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { checklist?.project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "checklistId": SyncJSON.uuid(checklist?.id),
            "title": .string(title),
            "isDone": .bool(isDone),
            "completedAt": SyncJSON.date(completedAt),
            "photoId": SyncJSON.uuid(photoID),
            "sortOrder": .int(sortOrder),
        ]
    }
}

extension Report: SyncPushable {
    static var syncEntity: String { "report" }
    static func idPredicate(_ id: UUID) -> Predicate<Report> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "title": .string(title),
            "photoIds": SyncJSON.uuids(photoIDs),
            "photoNotes": SyncJSON.noteMap(photoNotes),
            "layout": .string(layout.rawValue),
            "includesChecklistSummary": .bool(includesChecklistSummary),
            "pdfFileName": SyncJSON.optString(pdfFileName),
        ]
    }
}

extension BeforeAfterPair: SyncPushable {
    static var syncEntity: String { "beforeAfterPair" }
    static func idPredicate(_ id: UUID) -> Predicate<BeforeAfterPair> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "beforePhotoId": .string(beforePhotoID.uuidString),
            "afterPhotoId": .string(afterPhotoID.uuidString),
            "layout": .string(layout.rawValue),
        ]
    }
}

extension Page: SyncPushable {
    static var syncEntity: String { "page" }
    static func idPredicate(_ id: UUID) -> Predicate<Page> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "authorMemberId": SyncJSON.uuid(author?.id),
            "title": .string(title),
            "contentData": SyncJSON.blob(contentData),
            "sortOrder": .int(sortOrder),
            "pdfFileName": SyncJSON.optString(pdfFileName),
        ]
    }
}

extension Measurement: SyncPushable {
    static var syncEntity: String { "measurement" }
    static func idPredicate(_ id: UUID) -> Predicate<Measurement> { #Predicate { $0.id == id } }
    func syncOrganizationID(activeOrg: UUID) -> UUID? { project?.organization?.id }
    func syncPayload() -> SyncRow {
        [
            "projectId": SyncJSON.uuid(project?.id),
            "capturedAt": SyncJSON.date(capturedAt),
            "unit": .string(unit.rawValue),
            "segmentsData": SyncJSON.blob(segmentsData),
            "totalMeters": SyncJSON.double(totalMeters),
            "snapshotPhotoId": SyncJSON.uuid(snapshotPhotoID),
            "notes": .string(notes),
        ]
    }
}
