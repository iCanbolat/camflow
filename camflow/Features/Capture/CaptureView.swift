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

    @AppStorage("quickTagAfterCapture") private var quickTagAfterCapture = false

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
    @State private var lastCapturedThumbnail: UIImage?
    @State private var sessionCaptureCount = 0
    @State private var isCapturing = false
    @State private var shutterFlash = false
    @State private var baseZoom: CGFloat = 1
    @State private var quickTagPhoto: Photo?
    @State private var processingVideoCount = 0

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
                if activeSessionRunning && !isRecording {
                    modeToggle
                }
                bottomBar
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
        .sheet(isPresented: $isShowingProjectPicker) {
            ProjectPickerSheet(selectedProject: $selectedProject)
        }
        .sheet(item: $quickTagPhoto) { photo in
            TagPickerSheet(photos: [photo])
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
            CircleIconButton(systemImage: "xmark") { dismiss() }
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
                modeButton("Dual", mode: .dual)
            }
        }
        .background(.black.opacity(0.4), in: Capsule())
        .padding(.bottom, 12)
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

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $importItems, maxSelectionCount: 20, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .disabled(isRecording)

            Spacer()

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

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.15))
                    .frame(width: 56, height: 56)
                if let thumbnail = lastCapturedThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if sessionCaptureCount > 1 {
                        Text("\(sessionCaptureCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.tint, in: Circle())
                            .offset(x: 22, y: -22)
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
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

    private func capture() async {
        isCapturing = true
        defer { isCapturing = false }

        guard let data = await camera.capturePhoto() else { return }

        withAnimation(.easeOut(duration: 0.15)) { shutterFlash = true }
        withAnimation(.easeIn(duration: 0.15).delay(0.1)) { shutterFlash = false }

        let location = locationService.lastKnownLocation
        let store = PhotoStore(context: modelContext)
        guard let photo = try? await store.createPhoto(
            imageData: data,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            source: .camera,
            project: selectedProject
        ) else { return }

        sessionCaptureCount += 1
        if let thumbData = FileStorage.load(photo.thumbnailFileName, in: .photos) {
            lastCapturedThumbnail = UIImage(data: thumbData)
        }

        if quickTagAfterCapture {
            quickTagPhoto = photo
        }
    }

    /// Kicks off movie recording; the completion adopts the finished file.
    /// GPS and project assignment are frozen at record start (the picker is
    /// disabled while recording anyway).
    private func startVideoRecording() {
        let location = locationService.lastKnownLocation
        let project = selectedProject
        camera.startRecording { result in
            guard case .success(let url) = result else { return }
            Task { await saveVideo(tempURL: url, location: location, project: project) }
        }
    }

    private func startDualRecording() {
        guard let dualCamera else { return }
        let location = locationService.lastKnownLocation
        let project = selectedProject
        dualCamera.startRecording { result in
            switch result {
            case .success(.both(let back, let front)):
                Task { await compositeDualRecording(back: back, front: front, location: location, project: project) }
            case .success(.backOnly(let back)):
                // Front output failed — keep the footage as a plain video.
                Task { await saveVideo(tempURL: back, location: location, project: project) }
            case .failure:
                break
            }
        }
    }

    /// Runs the PiP composite without blocking the capture screen — the user
    /// can keep shooting while the pill spins. On composite failure the back
    /// recording is saved as a plain video so footage is never lost.
    private func compositeDualRecording(back: URL, front: URL, location: CLLocation?, project: Project?) async {
        processingVideoCount += 1
        defer { processingVideoCount -= 1 }
        do {
            let composite = try await VideoCompositor.compositePiP(backURL: back, frontURL: front)
            try? FileManager.default.removeItem(at: back)
            try? FileManager.default.removeItem(at: front)
            await saveVideo(tempURL: composite, location: location, project: project)
        } catch {
            try? FileManager.default.removeItem(at: front)
            await saveVideo(tempURL: back, location: location, project: project)
        }
    }

    private func saveVideo(tempURL: URL, location: CLLocation?, project: Project?) async {
        let store = PhotoStore(context: modelContext)
        guard let photo = try? await store.createVideo(
            tempURL: tempURL,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            project: project
        ) else { return }

        sessionCaptureCount += 1
        if let thumbData = FileStorage.load(photo.thumbnailFileName, in: .photos) {
            lastCapturedThumbnail = UIImage(data: thumbData)
        }
        if quickTagAfterCapture {
            quickTagPhoto = photo
        }
    }

    private func importSelectedPhotos() async {
        guard !importItems.isEmpty else { return }
        let items = importItems
        importItems = []

        let store = PhotoStore(context: modelContext)
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let photo = try? await store.importPhoto(imageData: data, project: selectedProject) else { continue }
            sessionCaptureCount += 1
            if let thumbData = FileStorage.load(photo.thumbnailFileName, in: .photos) {
                lastCapturedThumbnail = UIImage(data: thumbData)
            }
        }
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
                        isCreatingProject = true
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
        }
    }
}
