import AVFoundation
import Observation
import SwiftUI

/// AVFoundation capture pipeline: session lifecycle, flash, camera flip,
/// zoom, async photo capture, and movie recording.
@Observable
@MainActor
final class CameraService {
    enum Status {
        case idle
        case running
        case denied
        case unavailable
    }

    enum CaptureMode {
        case photo
        case video
    }

    static let maxVideoDuration: TimeInterval = 120

    // Thread-safe per AVFoundation docs; accessed from background for start/stop.
    nonisolated(unsafe) let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var activeProcessors: [Int64: PhotoCaptureProcessor] = [:]
    private var movieProcessor: MovieCaptureProcessor?

    private(set) var status: Status = .idle
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var captureMode: CaptureMode = .photo
    private(set) var isRecording = false
    private(set) var recordingStartedAt: Date?
    var isFlashOn = false

    func configureAndStart() async {
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

        if videoDeviceInput == nil {
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input),
                  session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                status = .unavailable
                return
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            session.commitConfiguration()
            videoDeviceInput = input
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }

        let session = self.session
        await Task.detached { session.startRunning() }.value
        status = .running
    }

    /// Reconfigures the session for photo or video capture. The `.photo` preset
    /// is incompatible with a movie output, and a connected mic input keeps the
    /// orange indicator lit, so both are attached only while in video mode.
    func setMode(_ mode: CaptureMode) async {
        guard mode != captureMode, !isRecording else { return }

        if mode == .video, AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        session.beginConfiguration()
        switch mode {
        case .video:
            session.sessionPreset = .hd1920x1080
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                movieOutput.maxRecordedDuration = CMTime(
                    seconds: Self.maxVideoDuration, preferredTimescale: 600
                )
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(micInput) {
                session.addInput(micInput)
                audioDeviceInput = micInput
            }
        case .photo:
            if session.outputs.contains(movieOutput) {
                session.removeOutput(movieOutput)
            }
            if let audioDeviceInput {
                session.removeInput(audioDeviceInput)
                self.audioDeviceInput = nil
            }
            session.sessionPreset = .photo
        }
        session.commitConfiguration()
        captureMode = mode
    }

    func stop() {
        let session = self.session
        Task.detached { session.stopRunning() }
        status = .idle
    }

    func flipCamera() {
        guard let currentInput = videoDeviceInput, !isRecording else { return }
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.removeInput(currentInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoDeviceInput = newInput
            position = newPosition
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        } else {
            session.addInput(currentInput)
        }
        session.commitConfiguration()
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let clamped = max(1, min(factor, min(device.activeFormat.videoMaxZoomFactor, 6)))
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        }
    }

    var zoomFactor: CGFloat {
        videoDeviceInput?.device.videoZoomFactor ?? 1
    }

    /// Captures a photo and returns its JPEG data.
    func capturePhoto() async -> Data? {
        guard status == .running else { return nil }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        if photoOutput.supportedFlashModes.contains(isFlashOn ? .on : .off) {
            settings.flashMode = isFlashOn ? .on : .off
        }

        return await withCheckedContinuation { continuation in
            let uniqueID = settings.uniqueID
            let processor = PhotoCaptureProcessor { data in
                Task { @MainActor [weak self] in
                    self?.activeProcessors.removeValue(forKey: uniqueID)
                    continuation.resume(returning: data)
                }
            }
            activeProcessors[uniqueID] = processor
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    /// Starts recording to a temp `.mov`; stops automatically at the 2-minute cap.
    /// The completion fires on the main actor with the finished file URL.
    func startRecording(onFinished: @escaping @MainActor (Result<URL, any Error>) -> Void) {
        guard captureMode == .video, status == .running, !isRecording,
              session.outputs.contains(movieOutput) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).mov")

        if let connection = movieOutput.connection(with: .video),
           let coordinator = rotationCoordinator {
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        // Torch resets on every session reconfigure, so it's set per recording.
        if isFlashOn, position == .back {
            setTorch(true)
        }

        let processor = MovieCaptureProcessor { result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setTorch(false)
                self.isRecording = false
                self.recordingStartedAt = nil
                self.movieProcessor = nil
                onFinished(result)
            }
        }
        movieProcessor = processor
        movieOutput.startRecording(to: tempURL, recordingDelegate: processor)
        isRecording = true
        recordingStartedAt = .now
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    private func setTorch(_ on: Bool) {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        if (try? device.lockForConfiguration()) != nil {
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }
}

/// Receives AVCapturePhotoOutput callbacks on its internal queue, so it must
/// stay nonisolated; results hop back to the main actor via the completion.
private nonisolated final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: @Sendable (Data?) -> Void

    init(completion: @escaping @Sendable (Data?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// Receives AVCaptureMovieFileOutput callbacks on its internal queue, so it must
/// stay nonisolated; results hop back to the main actor via the completion.
/// Shared with DualCameraService, which runs one per movie output.
nonisolated final class MovieCaptureProcessor: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completion: @Sendable (Result<URL, any Error>) -> Void

    init(completion: @escaping @Sendable (Result<URL, any Error>) -> Void) {
        self.completion = completion
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        // Hitting maxRecordedDuration (or disk-full) surfaces as an "error" even
        // though the file is valid — AVFoundation flags those via this key.
        if let error {
            let finished = ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
            completion(finished ? .success(outputFileURL) : .failure(error))
        } else {
            completion(.success(outputFileURL))
        }
    }
}

/// SwiftUI wrapper for the camera preview layer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
