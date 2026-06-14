import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

/// Full-screen camera: project selector with nearest-project suggestion,
/// GPS-stamped capture, library import, flash/flip/zoom.
struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.updatedAt, order: .reverse)
    private var allProjects: [Project]

    private var projects: [Project] {
        allProjects.filter { $0.organization?.id == session.activeOrganizationID }
    }

    /// Capture screen mode. Photo/video run on `CameraService`; dual swaps the
    /// whole session for `DualCameraService` (multicam needs its own graph).
    private enum UIMode {
        case photo
        case video
        case dual
    }

    @State private var camera = CameraService()
    @State private var dualCamera: DualCameraService?
    @State private var uiMode: UIMode = .photo
    @State private var selectedProject: Project?
    @State private var hasAutoSuggested = false
    @State private var isShowingProjectPicker = false
    @State private var importItems: [PhotosPickerItem] = []
    /// Captured-but-not-yet-saved media for this session. Persisted on "Done".
    @State private var drafts: [CapturedDraft] = []
    @State private var isShowingReview = false
    @State private var isShowingAnnotation = false
    @State private var isSubmitting = false
    @State private var isConfirmingDiscard = false
    /// The inline description bar auto-hides ~2s after each capture (unless the
    /// field is focused). `descriptionBarTimerID` restarts that countdown.
    @State private var isDescriptionBarVisible = false
    @State private var descriptionBarTimerID = 0
    @FocusState private var isDescriptionFocused: Bool
    @State private var isCapturing = false
    @State private var shutterFlash = false
    @State private var baseZoom: CGFloat = 1
    @State private var processingVideoCount = 0
    @State private var upgradeContext: UpgradeContext?

    private var isRecording: Bool {
        camera.isRecording || (dualCamera?.isRecording ?? false)
    }

    private var recordingStartedAt: Date? {
        camera.recordingStartedAt ?? dualCamera?.recordingStartedAt
    }

    private var activeSessionRunning: Bool {
        uiMode == .dual ? dualCamera?.status == .running : camera.status == .running
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            cameraLayer

            if shutterFlash {
                Color.white.ignoresSafeArea()
            }

            // Tap anywhere outside the field (while editing) to dismiss the keyboard.
            if isDescriptionFocused {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { isDescriptionFocused = false }
            }

            VStack {
                topBar
                if isRecording {
                    recordingPill
                        .padding(.top, 12)
                }
                if processingVideoCount > 0 {
                    processingPill
                        .padding(.top, 8)
                }
                Spacer()
                if !drafts.isEmpty && isDescriptionBarVisible {
                    descriptionBar
                        .transition(.opacity)
                }
                if activeSessionRunning && !isRecording {
                    modeToggle
                }
                bottomBar
            }

            if isSubmitting {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }
        }
        .statusBarHidden()
        .task {
            await camera.configureAndStart()
            locationService.startUpdates()
            suggestNearestProjectIfNeeded()
        }
        .onDisappear {
            camera.stop()
            dualCamera?.stop()
        }
        .onChange(of: locationService.lastKnownLocation) {
            suggestNearestProjectIfNeeded()
        }
        .onChange(of: importItems) {
            Task { await importSelectedPhotos() }
        }
        .onChange(of: drafts.count) { oldValue, newValue in
            // A fresh capture re-shows the description bar and restarts its timer.
            if newValue > oldValue { revealDescriptionBar() }
        }
        .onChange(of: isDescriptionFocused) { _, focused in
            if focused {
                isDescriptionBarVisible = true
            } else {
                descriptionBarTimerID += 1
            }
        }
        .task(id: descriptionBarTimerID) {
            guard isDescriptionBarVisible else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !isDescriptionFocused else { return }
            withAnimation(.easeInOut(duration: 0.3)) { isDescriptionBarVisible = false }
        }
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(selectedProject: $selectedProject)
        }
        .sheet(item: $upgradeContext) { context in
            UpgradePromptSheet(context: context)
        }
        .fullScreenCover(isPresented: $isShowingReview) {
            DraftReviewView(
                drafts: $drafts,
                projectName: selectedProject?.name,
                onSubmit: { await submitDrafts() }
            )
        }
        .fullScreenCover(isPresented: $isShowingAnnotation) {
            if let draft = drafts.last {
                AnnotationEditorView(
                    loadImage: { draftPhotoImage(draft) },
                    annotationData: draft.annotationData,
                    onSave: { draft.annotationData = $0 }
                )
            }
        }
        .confirmationDialog(
            "Discard \(drafts.count) capture\(drafts.count == 1 ? "" : "s")?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { discardAndDismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        if uiMode == .dual, let dualCamera {
            dualCameraLayer(dualCamera)
        } else {
            singleCameraLayer
        }
    }

    @ViewBuilder
    private func dualCameraLayer(_ dual: DualCameraService) -> some View {
        switch dual.status {
        case .running:
            MultiCamPreviewView(previewLayer: dual.backPreviewLayer)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    // Live PiP mirror of VideoCompositor.Layout: the composite
                    // bakes the front clip into the same corner.
                    MultiCamPreviewView(previewLayer: dual.frontPreviewLayer)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.6), lineWidth: 1)
                        }
                        .padding(.top, 72)
                        .padding(.trailing, 16)
                }
        case .denied:
            cameraFallback(
                systemImage: "video.slash.fill",
                message: "Camera access is disabled. Enable it in Settings to capture photos.",
                showsSettingsButton: true
            )
        case .unavailable:
            cameraFallback(
                systemImage: "camera.metering.unknown",
                message: "Dual capture isn't available on this device.",
                showsSettingsButton: false
            )
        case .idle:
            ProgressView()
                .tint(.white)
        }
    }

    @ViewBuilder
    private var singleCameraLayer: some View {
        switch camera.status {
        case .running:
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            camera.setZoom(baseZoom * value.magnification)
                        }
                        .onEnded { _ in
                            baseZoom = camera.zoomFactor
                        }
                )
        case .denied:
            cameraFallback(
                systemImage: "video.slash.fill",
                message: "Camera access is disabled. Enable it in Settings to capture photos.",
                showsSettingsButton: true
            )
        case .unavailable:
            cameraFallback(
                systemImage: "camera.metering.unknown",
                message: "No camera available on this device. You can still import photos from your library.",
                showsSettingsButton: false
            )
        case .idle:
            ProgressView()
                .tint(.white)
        }
    }

    private func cameraFallback(systemImage: String, message: LocalizedStringKey, showsSettingsButton: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            if showsSettingsButton {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemImage: "xmark") { closeTapped() }
                .disabled(isRecording)

            PhotosPicker(selection: $importItems, maxSelectionCount: 20, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .disabled(isRecording)

            Spacer()

            Button {
                isShowingProjectPicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedProject == nil ? "folder.badge.questionmark" : "folder.fill")
                        .font(.caption)
                    Text(selectedProject?.name ?? String(localized: "Select Project"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selectedProject == nil ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(.tint), in: Capsule())
            }
            .disabled(isRecording)

            Spacer()

            // Flash and flip apply to the single-cam session only; in dual
            // mode the cameras are fixed (back = main, front = PiP).
            if uiMode != .dual {
                CircleIconButton(systemImage: camera.isFlashOn ? "bolt.fill" : "bolt.slash.fill") {
                    camera.isFlashOn.toggle()
                }
                CircleIconButton(systemImage: "arrow.triangle.2.circlepath.camera.fill") {
                    camera.flipCamera()
                }
                .disabled(isRecording)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var recordingPill: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = recordingStartedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("/ 2:00")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
        }
    }

    private var processingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .controlSize(.small)
            Text("Processing video…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton("Photo", mode: .photo)
            modeButton("Video", mode: .video)
            if DualCameraService.isSupported {
                if session.activePlan.includesDualCapture {
                    modeButton("Dual", mode: .dual)
                } else {
                    lockedDualButton
                }
            }
        }
        .background(.black.opacity(0.4), in: Capsule())
        .padding(.bottom, 12)
    }

    private var lockedDualButton: some View {
        Button {
            upgradeContext = .dualCapture
        } label: {
            HStack(spacing: 4) {
                Text("Dual")
                Image(systemName: "lock.fill")
                    .font(.caption2)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }

    private func modeButton(_ title: LocalizedStringKey, mode: UIMode) -> some View {
        Button {
            Task { await switchMode(to: mode) }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(uiMode == mode ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    uiMode == mode ? AnyShapeStyle(.white) : AnyShapeStyle(.clear),
                    in: Capsule()
                )
        }
    }

    /// Photo↔video reconfigure the single session; entering/leaving Dual swaps
    /// between CameraService and DualCameraService entirely (multicam can't
    /// coexist with the regular session).
    private func switchMode(to mode: UIMode) async {
        guard mode != uiMode, !isRecording else { return }
        if mode == .dual && !session.activePlan.includesDualCapture {
            upgradeContext = .dualCapture
            return
        }
        switch (uiMode, mode) {
        case (_, .dual):
            camera.stop()
            let dual = DualCameraService()
            dualCamera = dual
            uiMode = .dual
            await dual.configureAndStart()
        case (.dual, _):
            dualCamera?.stop()
            dualCamera = nil
            uiMode = mode
            await camera.configureAndStart()
            await camera.setMode(mode == .photo ? .photo : .video)
        default:
            uiMode = mode
            await camera.setMode(mode == .photo ? .photo : .video)
        }
    }

    /// After-capture editor for the most recent draft: thumbnail, inline
    /// description field, and (photos only) a shortcut into the annotation editor.
    @ViewBuilder
    private var descriptionBar: some View {
        if let draft = drafts.last {
            HStack(spacing: 12) {
                Image(uiImage: draft.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture { isShowingReview = true }

                TextField("Description", text: Bindable(draft).caption)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .submitLabel(.done)
                    .focused($isDescriptionFocused)

                if !draft.isVideo {
                    Button {
                        isShowingAnnotation = true
                    } label: {
                        Image(systemName: "scribble.variable")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var bottomBar: some View {
        HStack {
            captureStackButton
                .frame(maxWidth: .infinity, alignment: .leading)

            shutterButton

            doneButton
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    /// Bottom-left: the captured batch. Tap to review/edit side by side.
    @ViewBuilder
    private var captureStackButton: some View {
        if let thumbnail = drafts.last?.thumbnail {
            Button {
                isShowingReview = true
            } label: {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) {
                        if drafts.count > 1 {
                            Text("\(drafts.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.tint, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                    }
            }
            .disabled(isRecording)
        } else {
            Color.clear.frame(width: 56, height: 56)
        }
    }

    private var shutterButton: some View {
        Button {
            switch uiMode {
            case .photo:
                Task { await capture() }
            case .video:
                if camera.isRecording {
                    camera.stopRecording()
                } else {
                    startVideoRecording()
                }
            case .dual:
                if dualCamera?.isRecording == true {
                    dualCamera?.stopRecording()
                } else {
                    startDualRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                if uiMode == .photo {
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                        .scaleEffect(isCapturing ? 0.85 : 1)
                } else if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 62, height: 62)
                }
            }
        }
        .disabled(!activeSessionRunning || isCapturing)
        .opacity(activeSessionRunning ? 1 : 0.4)
        .animation(.spring(duration: 0.2), value: isCapturing)
        .animation(.spring(duration: 0.2), value: isRecording)
    }

    /// Bottom-right: submit the whole batch to the selected project.
    private var doneButton: some View {
        Button {
            Task { await submitDrafts() }
        } label: {
            Text("Done")
                .font(.headline)
                .foregroundStyle(drafts.isEmpty ? .white.opacity(0.4) : .black)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    drafts.isEmpty ? AnyShapeStyle(.white.opacity(0.15)) : AnyShapeStyle(.white),
                    in: Capsule()
                )
        }
        .disabled(drafts.isEmpty || isSubmitting || isRecording)
    }

    // MARK: - Actions

    /// Suggests the closest project within 500 m once per camera session.
    private func suggestNearestProjectIfNeeded() {
        guard !hasAutoSuggested,
              selectedProject == nil,
              let location = locationService.lastKnownLocation else { return }

        let nearest = projects
            .compactMap { project -> (Project, CLLocationDistance)? in
                guard let lat = project.latitude, let lon = project.longitude else { return nil }
                let distance = location.distance(from: CLLocation(latitude: lat, longitude: lon))
                return (project, distance)
            }
            .filter { $0.1 <= 500 }
            .min { $0.1 < $1.1 }

        if let (project, _) = nearest {
            selectedProject = project
            hasAutoSuggested = true
        }
    }

    /// Shows the inline description bar and (re)starts its auto-hide countdown.
    private func revealDescriptionBar() {
        withAnimation(.easeInOut(duration: 0.25)) { isDescriptionBarVisible = true }
        descriptionBarTimerID += 1
    }

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }

        guard let data = await camera.capturePhoto() else { return }

        withAnimation(.easeOut(duration: 0.15)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.15).delay(0.1)) { shutterFlash = false }

        let location = locationService.lastKnownLocation
        let thumbnail = await Task.detached {
            ImageProcessor.makeThumbnail(from: data).flatMap(UIImage.init(data:))
        }.value

        drafts.append(CapturedDraft(
            media: .photo(imageData: data),
            thumbnail: thumbnail ?? UIImage(data: data) ?? UIImage(),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            source: .camera
        ))
    }

    /// Kicks off movie recording; the completion adopts the finished file.
    /// GPS and project assignment are frozen at record start (the picker is
    /// disabled while recording anyway).
    private func startVideoRecording() {
        let location = locationService.lastKnownLocation
        camera.startRecording { result in
            guard case .success(let url) = result else { return }
            Task { await addVideoDraft(tempURL: url, location: location) }
        }
    }

    private func startDualRecording() {
        guard let dualCamera else { return }
        let location = locationService.lastKnownLocation
        dualCamera.startRecording { result in
            switch result {
            case .success(.both(let back, let front)):
                Task { await compositeDualRecording(back: back, front: front, location: location) }
            case .success(.backOnly(let back)):
                // Front output failed — keep the footage as a plain video.
                Task { await addVideoDraft(tempURL: back, location: location) }
            case .failure:
                break
            }
        }
    }

    /// Runs the PiP composite without blocking the capture screen — the user
    /// can keep shooting while the pill spins. On composite failure the back
    /// recording is kept as a plain video so footage is never lost.
    private func compositeDualRecording(back: URL, front: URL, location: CLLocation?) async {
        processingVideoCount += 1
        defer { processingVideoCount -= 1 }
        do {
            let composite = try await VideoCompositor.compositePiP(backURL: back, frontURL: front)
            try? FileManager.default.removeItem(at: back)
            try? FileManager.default.removeItem(at: front)
            await addVideoDraft(tempURL: composite, location: location)
        } catch {
            try? FileManager.default.removeItem(at: front)
            await addVideoDraft(tempURL: back, location: location)
        }
    }

    /// Adds a finished recording to the batch as a draft. The temp file stays
    /// on disk and is moved into the store (on submit) or deleted (on discard) —
    /// video bytes are never held in memory.
    private func addVideoDraft(tempURL: URL, location: CLLocation?) async {
        let info = await Task.detached { () -> (UIImage?, Double?) in
            let duration = await VideoProcessor.duration(of: tempURL)
            let thumbnail = await VideoProcessor.makeThumbnail(forVideoAt: tempURL).flatMap(UIImage.init(data:))
            return (thumbnail, duration)
        }.value

        drafts.append(CapturedDraft(
            media: .video(url: tempURL, duration: info.1),
            thumbnail: info.0 ?? UIImage(),
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            source: .camera
        ))
    }

    private func importSelectedPhotos() async {
        guard !importItems.isEmpty else { return }
        let items = importItems
        importItems = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let (metadata, thumbnail) = await Task.detached { () -> (ImageProcessor.ImportedMetadata, UIImage?) in
                let metadata = ImageProcessor.metadata(from: data)
                let thumbnail = ImageProcessor.makeThumbnail(from: data).flatMap(UIImage.init(data:))
                return (metadata, thumbnail)
            }.value

            drafts.append(CapturedDraft(
                media: .photo(imageData: data),
                thumbnail: thumbnail ?? UIImage(data: data) ?? UIImage(),
                capturedAt: metadata.capturedAt ?? .now,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                source: .imported
            ))
        }
    }

    // MARK: - Batch submit / discard

    /// Persists every draft to the selected project, applying its caption and
    /// (photos only) annotation, then closes the camera.
    private func submitDrafts() async {
        guard !drafts.isEmpty else { dismiss(); return }
        isSubmitting = true
        defer { isSubmitting = false }

        let store = PhotoStore(context: modelContext)
        let author = session.activeMembership
        for draft in drafts {
            let caption = draft.caption.trimmingCharacters(in: .whitespaces)
            switch draft.media {
            case .photo(let imageData):
                guard let photo = try? await store.createPhoto(
                    imageData: imageData,
                    capturedAt: draft.capturedAt,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    source: draft.source,
                    project: selectedProject,
                    author: author
                ) else { continue }
                if !caption.isEmpty { photo.caption = caption }
                photo.annotationData = draft.annotationData
                store.touch(photo)
            case .video(let url, _):
                guard let photo = try? await store.createVideo(
                    tempURL: url,
                    capturedAt: draft.capturedAt,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    project: selectedProject,
                    author: author
                ) else { continue }
                if !caption.isEmpty { photo.caption = caption }
                store.touch(photo)
            }
        }
        drafts.removeAll()
        dismiss()
    }

    private func closeTapped() {
        if drafts.isEmpty {
            dismiss()
        } else {
            isConfirmingDiscard = true
        }
    }

    /// Throws away the batch, deleting any pending video temp files so they
    /// don't leak, then closes the camera.
    private func discardAndDismiss() {
        for draft in drafts {
            if let url = draft.videoURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        drafts.removeAll()
        dismiss()
    }

    /// Decoded full-resolution image for a photo draft (annotation editor input).
    private func draftPhotoImage(_ draft: CapturedDraft) -> UIImage? {
        if case .photo(let data) = draft.media {
            return UIImage(data: data)
        }
        return nil
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.15), in: Circle())
        }
    }
}

/// Project chooser for the capture screen: search, unassigned, quick create.
struct ProjectPickerSheet: View {
    @Binding var selectedProject: Project?

    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session

    @Query(filter: #Predicate<Project> { $0.deletedAt == nil }, sort: \Project.updatedAt, order: .reverse)
    private var allProjects: [Project]

    @State private var searchText = ""
    @State private var isCreatingProject = false
    @State private var upgradeContext: UpgradeContext?

    private var projects: [Project] {
        allProjects.filter { $0.organization?.id == session.activeOrganizationID }
    }

    private var filteredProjects: [Project] {
        guard !searchText.isEmpty else { return projects }
        return projects.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedProject = nil
                    dismiss()
                } label: {
                    HStack {
                        Label("Unassigned", systemImage: "tray")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedProject == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(filteredProjects) { project in
                    Button {
                        selectedProject = project
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .foregroundStyle(.primary)
                                if !project.address.isEmpty {
                                    Text(project.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if selectedProject?.id == project.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search projects")
            .navigationTitle("Assign to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if session.activeOrganization?.canAddProject ?? true {
                            isCreatingProject = true
                        } else {
                            upgradeContext = .projectLimit
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreatingProject) {
                ProjectEditorView()
            }
            .sheet(item: $upgradeContext) { context in
                UpgradePromptSheet(context: context)
            }
        }
    }
}
