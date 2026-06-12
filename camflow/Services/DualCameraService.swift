import AVFoundation
import Observation
import SwiftUI

/// Front+back simultaneous recording on multicam-capable devices. Owns an
/// `AVCaptureMultiCamSession` with a manually wired graph: two movie file
/// outputs (audio on the back/master one) and two preview layers. Lives only
/// while the capture screen is in Dual mode; `CameraService` keeps handling
/// single-cam photo/video.
@Observable
@MainActor
final class DualCameraService {
    enum Status {
        case idle
        case running
        case denied
        case unavailable
    }

    /// What a finished dual recording produced.
    enum RecordingOutcome {
        case both(back: URL, front: URL)
        /// Front output failed but the back file is valid — caller saves it as
        /// a plain single-cam video so footage is never lost.
        case backOnly(URL)
    }

    static var isSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    // Thread-safe per AVFoundation docs; accessed from background for start/stop.
    nonisolated(unsafe) let session = AVCaptureMultiCamSession()

    let backPreviewLayer = AVCaptureVideoPreviewLayer()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()

    private let backOutput = AVCaptureMovieFileOutput()
    private let frontOutput = AVCaptureMovieFileOutput()
    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var backRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var frontRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var pressureObservation: NSKeyValueObservation?

    private var backProcessor: MovieCaptureProcessor?
    private var frontProcessor: MovieCaptureProcessor?
    private var pendingBack: Result<URL, any Error>?
    private var pendingFront: Result<URL, any Error>?
    private var onFinished: (@MainActor (Result<RecordingOutcome, any Error>) -> Void)?

    private(set) var status: Status = .idle
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?

    func configureAndStart() async {
        guard Self.isSupported else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        case .denied, .restricted:
            status = .denied
            return
        default:
            break
        }

        if backInput == nil {
            guard configureGraph() else {
                status = .unavailable
                return
            }
        }

        let session = self.session
        await Task.detached { session.startRunning() }.value
        status = .running
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
        status = .idle
    }

    /// Builds the manual multicam graph. Returns false when any piece can't be
    /// attached (caller surfaces `.unavailable`).
    private func configureGraph() -> Bool {
        guard let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return false
        }

        // No presets on a multicam session — formats are picked per device.
        // Back gets 1080p; front 720p (rendered at ~30% width in the PiP, and
        // the smaller format materially cuts hardware cost).
        Self.applyMultiCamFormat(to: backDevice, width: 1920, height: 1080)
        Self.applyMultiCamFormat(to: frontDevice, width: 1280, height: 720)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let backInput = try? AVCaptureDeviceInput(device: backDevice),
              let frontInput = try? AVCaptureDeviceInput(device: frontDevice),
              session.canAddInput(backInput),
              session.canAddInput(frontInput) else {
            return false
        }
        session.addInputWithNoConnections(backInput)
        session.addInputWithNoConnections(frontInput)
        self.backInput = backInput
        self.frontInput = frontInput

        guard session.canAddOutput(backOutput), session.canAddOutput(frontOutput) else {
            return false
        }
        session.addOutputWithNoConnections(backOutput)
        session.addOutputWithNoConnections(frontOutput)

        guard let backPort = backInput.ports(for: .video, sourceDeviceType: backDevice.deviceType, sourceDevicePosition: .back).first,
              let frontPort = frontInput.ports(for: .video, sourceDeviceType: frontDevice.deviceType, sourceDevicePosition: .front).first else {
            return false
        }

        let backConnection = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
        let frontConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        guard session.canAddConnection(backConnection), session.canAddConnection(frontConnection) else {
            return false
        }
        session.addConnection(backConnection)
        session.addConnection(frontConnection)

        // Audio rides on the back (master) recording only.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInputWithNoConnections(micInput)
            if let audioPort = micInput.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: .unspecified).first {
                let audioConnection = AVCaptureConnection(inputPorts: [audioPort], output: backOutput)
                if session.canAddConnection(audioConnection) {
                    session.addConnection(audioConnection)
                }
            }
        }

        backPreviewLayer.setSessionWithNoConnection(session)
        frontPreviewLayer.setSessionWithNoConnection(session)
        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
        let backPreview = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backPreviewLayer)
        let frontPreview = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreviewLayer)
        guard session.canAddConnection(backPreview), session.canAddConnection(frontPreview) else {
            return false
        }
        session.addConnection(backPreview)
        session.addConnection(frontPreview)

        backOutput.maxRecordedDuration = CMTime(
            seconds: CameraService.maxVideoDuration, preferredTimescale: 600
        )

        backRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: backDevice, previewLayer: nil)
        frontRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: frontDevice, previewLayer: nil)

        // Multicam is the thermal worst case: bail out of recording on shutdown
        // pressure rather than letting the system kill the session.
        pressureObservation = backDevice.observe(\.systemPressureState, options: [.new]) { [weak self] _, change in
            guard change.newValue?.level == .shutdown else { return }
            Task { @MainActor in self?.stopRecording() }
        }
        return true
    }

    /// Picks the smallest multicam-capable format matching the target size
    /// (preferring binned ones — cheaper on hardware cost), at 30 fps.
    nonisolated private static func applyMultiCamFormat(to device: AVCaptureDevice, width: Int32, height: Int32) {
        let candidates = device.formats.filter(\.isMultiCamSupported)
        let matching = candidates.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width == width && dims.height == height
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }
        guard let format = matching.first(where: \.isVideoBinned) ?? matching.first ?? candidates.first else {
            return
        }
        if (try? device.lockForConfiguration()) != nil {
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        }
    }

    /// Starts both outputs back-to-back. The back output is the master: its
    /// 2-minute cap (or a stop tap) ends the front one too, and the completion
    /// fires once both files are final.
    func startRecording(onFinished: @escaping @MainActor (Result<RecordingOutcome, any Error>) -> Void) {
        guard status == .running, !isRecording else { return }

        pendingBack = nil
        pendingFront = nil
        self.onFinished = onFinished

        applyRotation(to: backOutput, coordinator: backRotationCoordinator)
        applyRotation(to: frontOutput, coordinator: frontRotationCoordinator)

        let backURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)_back.mov")
        let frontURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)_front.mov")

        let backProcessor = MovieCaptureProcessor { result in
            Task { @MainActor [weak self] in self?.finishBack(result) }
        }
        let frontProcessor = MovieCaptureProcessor { result in
            Task { @MainActor [weak self] in self?.finishFront(result) }
        }
        self.backProcessor = backProcessor
        self.frontProcessor = frontProcessor

        backOutput.startRecording(to: backURL, recordingDelegate: backProcessor)
        frontOutput.startRecording(to: frontURL, recordingDelegate: frontProcessor)
        isRecording = true
        recordingStartedAt = .now
    }

    func stopRecording() {
        guard isRecording else { return }
        // Stopping the back (master) output cascades to the front in finishBack,
        // which also covers the maxRecordedDuration auto-stop path.
        backOutput.stopRecording()
    }

    private func applyRotation(to output: AVCaptureMovieFileOutput, coordinator: AVCaptureDevice.RotationCoordinator?) {
        guard let coordinator, let connection = output.connection(with: .video) else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func finishBack(_ result: Result<URL, any Error>) {
        pendingBack = result
        if frontOutput.isRecording {
            frontOutput.stopRecording()
        }
        resolveIfComplete()
    }

    private func finishFront(_ result: Result<URL, any Error>) {
        pendingFront = result
        resolveIfComplete()
    }

    private func resolveIfComplete() {
        guard let back = pendingBack, let front = pendingFront, let onFinished else { return }
        isRecording = false
        recordingStartedAt = nil
        backProcessor = nil
        frontProcessor = nil
        pendingBack = nil
        pendingFront = nil
        self.onFinished = nil

        switch (back, front) {
        case (.success(let backURL), .success(let frontURL)):
            onFinished(.success(.both(back: backURL, front: frontURL)))
        case (.success(let backURL), .failure):
            onFinished(.success(.backOnly(backURL)))
        case (.failure(let error), .success(let frontURL)):
            try? FileManager.default.removeItem(at: frontURL)
            onFinished(.failure(error))
        case (.failure(let error), .failure):
            onFinished(.failure(error))
        }
    }
}

/// Hosts one of DualCameraService's preview layers in SwiftUI. The PiP look
/// comes from the SwiftUI container clipping the front layer's host view.
struct MultiCamPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    final class LayerHostView: UIView {
        var hostedLayer: CALayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostedLayer?.frame = bounds
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.layer.addSublayer(previewLayer)
        view.hostedLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}
}
