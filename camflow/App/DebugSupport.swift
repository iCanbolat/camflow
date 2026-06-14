#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import UIKit
import CryptoKit
import AVFoundation
import AVKit

/// Debug-only launch argument support, e.g. from the scheme or simctl:
///   -initialTab projects     → open on a specific tab
///   -seedSampleData YES      → insert a demo account, two orgs, projects + photos
///   -skipAuth YES            → sign in to the first seeded account and skip onboarding
///   -activeOrgName "<name>"  → select the active org by name
///   -planTier basic|pro|premium          → set the active org's plan tier
///   -activeRole admin|manager|standard   → set the current account's role in the active org
///   -debugScreen viewer      → open the photo viewer over the tab bar
///   -debugScreen annotation  → open the annotation editor over the tab bar
///   -debugScreen billing     → open Plan & Billing; upgradeprompt → the upsell sheet
///   -debugScreen notifications → the notifications sheet for the current member
///   -debugScreen inviteshare → the invite-link share sheet (seeded code CREW2345)
///   -debugScreen joinorg     → the join-organization screen for CREW2345
///   -debugScreen pageeditor  → open the rich-page block editor on the seeded page
///   -debugScreen pagepdf     → render + preview the seeded page as a PDF
///   -inviteURL "camflow://invite/CREW2345" → route an invite link through the
///       same parser as onOpenURL (simctl openurl triggers a system open-in-app
///       prompt that can't be tapped without UI automation)
/// `-seedSampleData YES` implies `-skipAuth YES` so screenshot runs land in-app;
/// pass an explicit `-skipAuth NO` to seed but still go through AuthView.
enum DebugSupport {
    static var initialTab: AppTab? {
        switch UserDefaults.standard.string(forKey: "initialTab") {
        case "projects": .projects
        case "team": .team
        case "more": .more
        case "home": .home
        default: nil
        }
    }

    static var debugScreen: String? {
        UserDefaults.standard.string(forKey: "debugScreen")
    }

    @MainActor
    static func seedSampleDataIfRequested(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "seedSampleData") else { return }

        let count = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        guard count == 0 else { return }

        // Demo account + two organizations so the Home switcher has entries.
        let account = Account(
            email: "demo@camflow.app",
            displayName: "Demo User",
            provider: .email,
            passwordHash: sha256("password"),
            colorHex: TagPalette.colors[0]
        )
        context.insert(account)

        let orgStore = OrganizationStore(context: context)
        // The demo account OWNS the primary org. A user owns at most one org, so
        // the secondary is owned by a separate synthetic account and the demo
        // account merely JOINS it as a member — that's what the switcher shows.
        let primary = orgStore.create(name: "Demo Construction Co.", owner: account)

        let skylineOwner = Account(
            email: "owner@skyline.app",
            displayName: "Skyline Owner",
            provider: .email,
            passwordHash: sha256("password"),
            colorHex: TagPalette.colors[2]
        )
        context.insert(skylineOwner)
        let secondary = orgStore.create(name: "Skyline Renovations", owner: skylineOwner)
        let demoInSecondary = OrgMember(
            name: account.displayName,
            phoneNumber: "",
            title: String(localized: "Manager"),
            role: .manager,
            status: .active,
            colorHex: account.colorHex,
            accountID: account.id
        )
        context.insert(demoInSecondary)
        demoInSecondary.organization = secondary

        let owner = primary.activeMembers.first { $0.role == .owner }

        let labels = (try? context.fetch(FetchDescriptor<ProjectLabel>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []

        let riverside = Project(
            name: "Riverside House",
            address: "Bebek, Beşiktaş, İstanbul",
            latitude: 41.0773,
            longitude: 29.0434,
            label: labels.first
        )
        let warehouse = Project(
            name: "Warehouse Re-roof",
            address: "İkitelli OSB, Başakşehir, İstanbul",
            latitude: 41.0931,
            longitude: 28.7980,
            label: labels.count > 1 ? labels[1] : nil
        )
        context.insert(riverside)
        context.insert(warehouse)
        riverside.organization = primary
        warehouse.organization = primary

        // A project in the second org so switching shows distinct data.
        let skylineLoft = Project(
            name: "Skyline Loft Remodel",
            address: "Karaköy, Beyoğlu, İstanbul",
            latitude: 41.0256,
            longitude: 28.9744,
            label: labels.first
        )
        context.insert(skylineLoft)
        skylineLoft.organization = secondary

        // Primary org demos the Pro tier and one member per role; Skyline stays
        // Basic (1 project + owner) so both plan limits are easy to exercise.
        primary.planTier = .pro

        let memberStore = MemberStore(context: context)
        let mehmet = memberStore.invite(
            name: "Mehmet Yılmaz",
            phoneNumber: "+90 532 111 22 33",
            title: "Site Foreman",
            role: .manager,
            projects: [riverside],
            organization: primary
        )
        let ayse = memberStore.invite(
            name: "Ayşe Demir",
            phoneNumber: "+90 533 444 55 66",
            title: "Electrician",
            role: .standard,
            projects: [riverside, warehouse],
            organization: primary
        )
        // Stable invite code so link/redemption flows are testable via
        // `simctl openurl camflow://invite/CREW2345` and -debugScreen.
        memberStore.assignInviteCode("CREW2345", to: ayse)
        memberStore.invite(
            name: "Leyla Kaya",
            phoneNumber: "+90 535 777 88 99",
            title: "Office Manager",
            role: .admin,
            projects: [riverside, warehouse],
            organization: primary
        )

        // Seeded after members so each sample photo/video gets an author.
        seedSamplePhotos(
            context: context,
            riverside: riverside,
            warehouse: warehouse,
            authors: [owner, mehmet, ayse].compactMap { $0 }
        )

        if let owner {
            seedSampleTasks(context: context, riverside: riverside, owner: owner, mehmet: mehmet, ayse: ayse)
        }

        seedSamplePages(context: context, project: riverside, author: owner)
    }

    /// Seeds one rich page (heading, paragraph, checklist, photo grid) so the
    /// Docs → Pages list, editor, and PDF export are verifiable in the simulator.
    @MainActor
    private static func seedSamplePages(context: ModelContext, project: Project, author: OrgMember?) {
        func heading(_ string: String, level: Int) -> PageBlock {
            var block = PageBlock.make(.heading)
            block.text = AttributedString(string)
            block.headingLevel = level
            return block
        }
        func paragraph(_ string: String) -> PageBlock {
            var block = PageBlock.make(.paragraph)
            block.text = AttributedString(string)
            return block
        }

        var blocks: [PageBlock] = [
            heading("Site Progress — Week 3", level: 1),
            paragraph("Framing is complete on the east wing. Electrical rough-in started Tuesday and is roughly half done. Drywall delivery is scheduled for next Monday."),
            PageBlock.make(.divider),
            heading("Open Items", level: 2),
        ]
        var checklist = PageBlock.make(.checklist)
        checklist.checklistItems = [
            PageChecklistItem(text: "Confirm panel labels", isDone: true),
            PageChecklistItem(text: "Order drywall materials", isDone: false),
            PageChecklistItem(text: "Schedule framing inspection", isDone: false),
        ]
        blocks.append(checklist)

        let photoIDs = project.activePhotos
            .filter { !$0.isVideo }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(4)
            .map(\.id)
        if !photoIDs.isEmpty {
            blocks.append(heading("Photos", level: 2))
            var grid = PageBlock.make(.photoGrid)
            grid.photoIDs = Array(photoIDs)
            grid.columns = 2
            grid.squareCrop = true
            grid.caption = "East wing progress"
            blocks.append(grid)
        }

        PageStore(context: context).create(
            title: "Site Progress — Week 3",
            document: PageDocument(blocks: blocks),
            project: project,
            author: author
        )
    }

    /// Signs the first seeded account in and skips onboarding so simulator runs
    /// land directly in the app. Triggered by `-skipAuth YES` (or implied by
    /// `-seedSampleData YES`).
    @MainActor
    static func applyAuthSkipIfRequested(session: Session, context: ModelContext) {
        let defaults = UserDefaults.standard
        // An explicit `-skipAuth NO` opts out even when `-seedSampleData YES`
        // would imply it, so seeded accounts can be exercised through AuthView.
        if defaults.object(forKey: "skipAuth") != nil, !defaults.bool(forKey: "skipAuth") { return }
        guard defaults.bool(forKey: "skipAuth") || defaults.bool(forKey: "seedSampleData") else { return }

        defaults.set(true, forKey: "hasSeenWelcome")
        defaults.set(true, forKey: "hasPrimedPermissions")

        if session.currentAccount == nil {
            let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.deletedAt == nil })
            if let account = (try? context.fetch(descriptor))?.first {
                session.signIn(account)
            }
        }

        // -activeOrgName "<name>" selects the active org through the app's own
        // Session (so it survives the simulator's preferences cache, unlike an
        // external `defaults write`).
        if let name = defaults.string(forKey: "activeOrgName"),
           let org = session.organizations.first(where: { $0.name == name }) {
            session.setActiveOrg(org)
        }

        // -planTier basic|pro|premium overrides the active org's plan.
        if let raw = defaults.string(forKey: "planTier"),
           let tier = PlanTier(rawValue: raw),
           let org = session.activeOrganization {
            OrganizationStore(context: context).setPlan(tier, for: org)
        }

        // -activeRole admin|manager|standard rewrites the current account's
        // member row in the active org. Works because `Session.activeRole`
        // prefers the membership row over the ownerAccountID fallback.
        if let raw = defaults.string(forKey: "activeRole"),
           let role = OrgMember.Role(rawValue: raw == "standard" ? "member" : raw),
           role != .owner,
           let membership = session.activeMembership {
            membership.role = role
        }
    }

    /// -inviteURL "<url>" feeds an invite link through `InviteLinks.code(from:)`
    /// exactly like the onOpenURL handler, so the join flow is verifiable in
    /// the simulator without tapping the system's open-in-app confirmation.
    @MainActor
    static func applyInviteURLIfRequested(session: Session) {
        guard let raw = UserDefaults.standard.string(forKey: "inviteURL"),
              let url = URL(string: raw),
              let code = InviteLinks.code(from: url) else { return }
        session.setPendingInvite(code: code)
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func seedSampleTasks(
        context: ModelContext,
        riverside: Project,
        owner: OrgMember,
        mehmet: OrgMember,
        ayse: OrgMember
    ) {
        let taskStore = TaskStore(context: context)

        let junctionTask = taskStore.create(
            title: "Fix junction box",
            note: "Relabel breaker panel and close up the junction in the hallway.",
            dueDate: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400 * 2),
            assignee: ayse,
            project: riverside
        )
        if let evidence = riverside.activePhotos.first {
            junctionTask.attachedPhotoIDs = [evidence.id]
        }
        taskStore.addComment(
            to: junctionTask,
            text: "Parts arrived this morning, starting after lunch.",
            mentionIDs: [],
            author: ayse
        )
        taskStore.addComment(
            to: junctionTask,
            text: "@Mehmet Yılmaz can you verify the panel labels tomorrow morning?",
            mentionIDs: [mehmet.id],
            author: owner
        )

        let materialsTask = taskStore.create(
            title: "Order drywall materials",
            assignee: mehmet,
            project: riverside
        )
        materialsTask.completedAt = Date.now.addingTimeInterval(-86_400)

        let checklistStore = ChecklistStore(context: context)
        checklistStore.createTemplate(
            name: "Roof Inspection",
            itemTitles: ["Check flashing", "Inspect shingles", "Document drainage", "Photograph penetrations"]
        )
        let walkthroughTemplate = checklistStore.createTemplate(
            name: "Final Walkthrough",
            itemTitles: ["All outlets working", "Paint touch-ups done", "Site cleaned"]
        )
        let walkthrough = checklistStore.create(
            name: "Final Walkthrough",
            template: walkthroughTemplate,
            assignee: mehmet,
            project: riverside
        )
        if let firstItem = walkthrough.sortedItems.first {
            checklistStore.toggleItem(firstItem)
        }

        // Notifications addressed to the current user (owner), so the bell is
        // populated with per-item control on a fresh seed. These exercise the
        // real fan-out paths (assignment + comment + mention).
        let notificationStore = NotificationStore(context: context)
        let ownerTask = taskStore.create(
            title: "Review final electrical sign-off",
            note: "Confirm the panel labels before the inspection.",
            dueDate: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400 * 3),
            assignee: owner,
            project: riverside
        )
        notificationStore.notifyTaskAssigned(ownerTask, assignee: owner, by: mehmet)
        // Ayşe @mentions the owner on her task → mention notification.
        taskStore.addComment(
            to: junctionTask,
            text: "@Demo User can you approve the updated materials list?",
            mentionIDs: [owner.id],
            author: ayse
        )
        // Mehmet comments on the owner's task → comment notification.
        taskStore.addComment(
            to: ownerTask,
            text: "Left the inspection report on your desk for review.",
            mentionIDs: [],
            author: mehmet
        )
        // Leave the assignment read, the two newer ones unread (badge shows 2).
        let seeded = (try? context.fetch(FetchDescriptor<AppNotification>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        if let assignment = seeded.first(where: { $0.recipient?.id == owner.id && $0.kind == .taskAssigned }) {
            notificationStore.markRead(assignment)
        }

        let riversidePhotos = riverside.activePhotos.sorted { $0.capturedAt > $1.capturedAt }
        if riversidePhotos.count >= 2 {
            BeforeAfterStore(context: context).create(
                beforePhotoID: riversidePhotos[1].id,
                afterPhotoID: riversidePhotos[0].id,
                layout: .sideBySide,
                project: riverside
            )
        }
    }

    @MainActor
    private static func seedSamplePhotos(context: ModelContext, riverside: Project, warehouse: Project, authors: [OrgMember] = []) {
        let samples: [(String, CGFloat, Project?)] = [
            ("Foundation", 0.08, riverside),
            ("Framing", 0.35, riverside),
            ("Electrical", 0.58, riverside),
            ("Roof Deck", 0.75, warehouse),
            ("Unassigned", 0.0, nil),
        ]

        for (offset, (title, hue, project)) in samples.enumerated() {
            guard let data = makeSampleImage(label: title, hue: hue) else { continue }
            let id = UUID()
            let fileName = "\(id.uuidString).jpg"
            let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
            guard (try? FileStorage.save(data, named: fileName, in: .photos)) != nil else { continue }
            if let thumbnail = ImageProcessor.makeThumbnail(from: data) {
                _ = try? FileStorage.save(thumbnail, named: thumbnailFileName, in: .photos)
            }

            let photo = Photo(
                fileName: fileName,
                thumbnailFileName: thumbnailFileName,
                capturedAt: Date.now.addingTimeInterval(Double(-offset) * 5400),
                latitude: project?.latitude.map { $0 + 0.0004 },
                longitude: project?.longitude.map { $0 - 0.0003 },
                source: .camera,
                project: project
            )
            photo.id = id

            // Round-robin authorship so distinct avatars/names are visible.
            if !authors.isEmpty {
                photo.author = authors[offset % authors.count]
            }

            // First sample arrives pre-annotated so overlay rendering is visible.
            if offset == 0 {
                photo.annotationData = AnnotationDocument(shapes: [
                    AnnotationShape(kind: .arrow, colorHex: "#FF6B35", points: [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.45, y: 0.45)]),
                    AnnotationShape(kind: .rectangle, colorHex: "#E0475B", points: [CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.8, y: 0.5)]),
                    AnnotationShape(kind: .text, colorHex: "#F7B32B", points: [CGPoint(x: 0.15, y: 0.12)], text: "Check this junction"),
                ]).encoded()
            }
            context.insert(photo)
        }

        seedSampleVideo(context: context, project: riverside, author: authors.first)
        seedSampleMeasurement(context: context, project: riverside)
    }

    /// Seeds one measurement (snapshot photo + two segments) so the Info
    /// section, detail sheet, and soft delete are verifiable in the simulator,
    /// where ARKit is unavailable.
    @MainActor
    private static func seedSampleMeasurement(context: ModelContext, project: Project) {
        guard let data = makeSampleImage(label: "Measure", hue: 0.45) else { return }
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let thumbnailFileName = "\(id.uuidString)_thumb.jpg"
        guard (try? FileStorage.save(data, named: fileName, in: .photos)) != nil else { return }
        if let thumbnail = ImageProcessor.makeThumbnail(from: data) {
            _ = try? FileStorage.save(thumbnail, named: thumbnailFileName, in: .photos)
        }

        let photo = Photo(
            fileName: fileName,
            thumbnailFileName: thumbnailFileName,
            latitude: project.latitude,
            longitude: project.longitude,
            source: .camera,
            project: project
        )
        photo.id = id
        context.insert(photo)

        let segments = [
            MeasurementSegment(start: SIMD3(0, 0, -1), end: SIMD3(1.24, 0, -1)),
            MeasurementSegment(start: SIMD3(1.24, 0, -1), end: SIMD3(1.24, 0.82, -1)),
        ]
        MeasurementStore(context: context).create(
            segments: segments,
            unit: .meters,
            snapshotPhotoID: photo.id,
            project: project
        )
    }

    /// Generates a short synthetic clip so video surfaces (grid badge, player
    /// page, share, exclusions) are verifiable in the simulator, where the
    /// camera doesn't exist. Runs async; the @Query-driven UI picks it up.
    @MainActor
    private static func seedSampleVideo(context: ModelContext, project: Project, author: OrgMember? = nil) {
        Task {
            guard let tempURL = await Task.detached(operation: { makeSampleVideo() }).value else { return }

            let id = UUID()
            let fileName = "\(id.uuidString).mov"
            let thumbnailFileName = "\(id.uuidString)_thumb.jpg"

            let duration = await VideoProcessor.duration(of: tempURL)
            if let thumbnail = await VideoProcessor.makeThumbnail(forVideoAt: tempURL) {
                _ = try? FileStorage.save(thumbnail, named: thumbnailFileName, in: .photos)
            }
            guard (try? FileStorage.adopt(fileAt: tempURL, named: fileName, in: .photos)) != nil else { return }

            let video = Photo(
                fileName: fileName,
                thumbnailFileName: thumbnailFileName,
                capturedAt: .now,
                latitude: project.latitude,
                longitude: project.longitude,
                source: .camera,
                mediaType: .video,
                durationSeconds: duration,
                project: project,
                author: author
            )
            video.id = id
            context.insert(video)
        }
    }

    /// Renders ~3s of animated gradient frames to a temp `.mov` (H.264 960×540).
    /// Also feeds the `-debugScreen pipcomposite` harness (two hues → two clips).
    nonisolated static func makeSampleVideo(seconds: Double = 3, fps: Int32 = 24, hueBase: CGFloat = 0.55) -> URL? {
        let size = CGSize(width: 960, height: 540)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(seconds * Double(fps))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            let progress = CGFloat(frame) / CGFloat(max(frameCount - 1, 1))
            guard let buffer = makeVideoFrame(size: size, progress: progress, hueBase: hueBase) else { return nil }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()

        // Debug-only synchronous wait; completion fires on a background queue.
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        return writer.status == .completed ? url : nil
    }

    /// One gradient frame with a dot sweeping across so playback visibly animates.
    nonisolated private static func makeVideoFrame(size: CGSize, progress: CGFloat, hueBase: CGFloat = 0.55) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
        )
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let hue = hueBase + 0.2 * progress
        let colors = [
            UIColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1).cgColor,
            UIColor(hue: hue, saturation: 0.8, brightness: 0.4, alpha: 1).cgColor,
        ]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
            context.drawLinearGradient(
                gradient, start: .zero,
                end: CGPoint(x: size.width, y: size.height), options: []
            )
        }
        context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        let x = size.width * (0.1 + 0.8 * progress)
        context.fillEllipse(in: CGRect(x: x - 28, y: size.height / 2 - 28, width: 56, height: 56))
        return buffer
    }

    /// Renders a gradient placeholder image so grids/viewer/annotations can be
    /// exercised in the simulator, where there is no camera.
    private static func makeSampleImage(label: String, hue: CGFloat) -> Data? {
        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [
                UIColor(hue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).cgColor,
                UIColor(hue: hue, saturation: 0.75, brightness: 0.45, alpha: 1).cgColor,
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
            ]
            let text = NSAttributedString(string: label, attributes: attributes)
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2))
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}

/// Presents viewer/annotation screens directly for simulator verification,
/// since tap automation isn't available.
struct DebugScreenHost: View {
    let kind: String

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Photo> { $0.deletedAt == nil }, sort: \Photo.capturedAt, order: .reverse)
    private var photos: [Photo]

    @Query(filter: #Predicate<ProjectTask> { $0.deletedAt == nil }, sort: \ProjectTask.createdAt)
    private var tasks: [ProjectTask]

    @Query(filter: #Predicate<Checklist> { $0.deletedAt == nil }, sort: \Checklist.createdAt)
    private var checklists: [Checklist]

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var projects: [Project]

    @Query(filter: #Predicate<BeforeAfterPair> { $0.deletedAt == nil }, sort: \BeforeAfterPair.createdAt)
    private var pairs: [BeforeAfterPair]

    @Query(filter: #Predicate<Measurement> { $0.deletedAt == nil }, sort: \Measurement.createdAt)
    private var measurements: [Measurement]

    @Query(filter: #Predicate<OrgMember> { $0.deletedAt == nil }, sort: \OrgMember.createdAt)
    private var members: [OrgMember]

    @Query(filter: #Predicate<Page> { $0.deletedAt == nil }, sort: \Page.updatedAt, order: .reverse)
    private var pages: [Page]

    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case "annotation":
                    if let photo = photos.first {
                        AnnotationEditorView(photo: photo, context: modelContext)
                    }
                case "share":
                    ShareOptionsSheet(photos: Array(photos.prefix(1)))
                case "task":
                    if let task = tasks.first {
                        TaskDetailView(task: task)
                    }
                case "checklist":
                    if let checklist = checklists.first {
                        ChecklistDetailView(checklist: checklist)
                    }
                case "notifications":
                    NotificationsView(recipientID: session.activeMembership?.id ?? UUID())
                case "report":
                    if let project = projects.first(where: { !$0.activePhotos.isEmpty }) {
                        ReportBuilderView(project: project)
                    }
                case "reportpdf":
                    DebugReportPDFView()
                case "pipcomposite":
                    DebugPiPCompositeView()
                case "measurements":
                    if let measurement = measurements.first {
                        MeasurementDetailSheet(measurement: measurement)
                    }
                case "beforeafter":
                    if let pair = pairs.first, let project = pair.project {
                        BeforeAfterComposerView(project: project, existingPair: pair)
                    }
                case "billing":
                    PlanBillingView()
                case "upgradeprompt":
                    UpgradePromptSheet(context: .projectLimit)
                case "inviteshare":
                    if let member = members.first(where: { $0.inviteCode != nil }) {
                        InviteShareSheet(member: member)
                    }
                case "joinorg":
                    JoinOrganizationView(code: "CREW2345")
                case "pageeditor":
                    if let page = pages.first, let project = page.project {
                        PageEditorView(page: page, project: project)
                    }
                case "pagepdf":
                    DebugPagePDFView()
                default:
                    PhotoViewerView(photos: photos)
                }
            }
            .navigationDestination(for: Photo.self) { photo in
                PhotoViewerView(photos: [photo])
            }
        }
    }
}

/// Generates two synthetic clips, runs the PiP composite, and plays the result
/// — the only way to iterate on VideoCompositor without a multicam device.
struct DebugPiPCompositeView: View {
    @State private var player: AVPlayer?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else if let errorText {
                ContentUnavailableView(errorText, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView("Compositing…")
            }
        }
        .task {
            guard player == nil else { return }
            let clips = await Task.detached {
                (DebugSupport.makeSampleVideo(hueBase: 0.58),
                 DebugSupport.makeSampleVideo(hueBase: 0.02))
            }.value
            guard let back = clips.0, let front = clips.1 else {
                errorText = "Sample clip generation failed"
                return
            }
            do {
                let output = try await VideoCompositor.compositePiP(backURL: back, frontURL: front)
                try? FileManager.default.removeItem(at: back)
                try? FileManager.default.removeItem(at: front)
                player = AVPlayer(url: output)
            } catch {
                errorText = "Composite failed: \(error.localizedDescription)"
            }
        }
    }
}

/// Auto-generates a report PDF from the first project so the renderer can be
/// verified in the simulator without tap automation.
struct DebugReportPDFView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.name)
    private var projects: [Project]

    @State private var pdfURL: URL?

    var body: some View {
        Group {
            if let pdfURL {
                PDFKitView(url: pdfURL)
            } else {
                ProgressView()
            }
        }
        .task {
            guard pdfURL == nil,
                  let project = projects.first(where: { !$0.activePhotos.isEmpty }) else { return }
            let photos = project.activePhotos.sorted { $0.capturedAt > $1.capturedAt }
            let store = ReportStore(context: modelContext)
            let report = store.create(
                title: "\(project.name) — Site Progress",
                photoIDs: photos.map(\.id),
                photoNotes: photos.first.map { [$0.id: "Junction box relabeled and closed up."] } ?? [:],
                layout: .twoPerPage,
                includesChecklistSummary: true,
                project: project
            )
            if let url = await ReportPDFRenderer.render(report: report, project: project, organization: session.activeOrganization) {
                report.pdfFileName = url.lastPathComponent
                pdfURL = url
            }
        }
    }
}

/// Auto-generates a page PDF from the first seeded page so the renderer can be
/// verified in the simulator without tap automation.
struct DebugPagePDFView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Page> { $0.deletedAt == nil }, sort: \Page.updatedAt, order: .reverse)
    private var pages: [Page]

    @State private var pdfURL: URL?

    var body: some View {
        Group {
            if let pdfURL {
                PDFKitView(url: pdfURL)
            } else {
                ProgressView()
            }
        }
        .task {
            guard pdfURL == nil, let page = pages.first, let project = page.project else { return }
            if let url = await PagePDFRenderer.render(page: page, project: project, organization: session.activeOrganization) {
                page.pdfFileName = url.lastPathComponent
                pdfURL = url
            }
        }
    }
}
#endif
