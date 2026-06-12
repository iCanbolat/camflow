import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Merges a dual recording into one shareable file: the front clip becomes a
/// rounded-corner PiP over the back clip, audio comes from the back recording.
/// Everything here runs off the main actor on AVFoundation's queues.
nonisolated enum VideoCompositor {
    enum CompositeError: Error {
        case missingVideoTrack
        case exportFailed
    }

    /// PiP layout as fractions of the render size, mirrored by the live preview
    /// in CaptureView (top-trailing, ~30% width).
    enum Layout {
        static let widthFraction: CGFloat = 0.3
        static let margin: CGFloat = 0.04
        static let cornerRadiusFraction: CGFloat = 0.12
    }

    /// Composites the two recordings and returns the final `.mov` temp URL.
    /// The caller deletes the originals on success; on failure it should keep
    /// the back recording and save it as a plain single-cam video.
    static func compositePiP(backURL: URL, frontURL: URL) async throws -> URL {
        let backAsset = AVURLAsset(url: backURL)
        let frontAsset = AVURLAsset(url: frontURL)

        guard let backTrack = try await backAsset.loadTracks(withMediaType: .video).first,
              let frontTrack = try await frontAsset.loadTracks(withMediaType: .video).first else {
            throw CompositeError.missingVideoTrack
        }

        let backDuration = try await backAsset.load(.duration)
        let frontDuration = try await frontAsset.load(.duration)
        let (backNaturalSize, backTransform) = try await backTrack.load(.naturalSize, .preferredTransform)
        let frontTransform = try await frontTrack.load(.preferredTransform)

        let composition = AVMutableComposition()
        guard let compBack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compFront = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositeError.exportFailed
        }
        try compBack.insertTimeRange(CMTimeRange(start: .zero, duration: backDuration), of: backTrack, at: .zero)
        // The two outputs start ~10–100 ms apart; v1 aligns both at zero. If
        // PiP drift ever becomes noticeable, offset by the first-sample PTS.
        try compFront.insertTimeRange(
            CMTimeRange(start: .zero, duration: min(frontDuration, backDuration)),
            of: frontTrack,
            at: .zero
        )
        if let audioTrack = try await backAsset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: backDuration), of: audioTrack, at: .zero)
        }

        // Render size = the back track's display size (portrait capture means
        // natural size is landscape plus a 90° preferred transform).
        let backRect = CGRect(origin: .zero, size: backNaturalSize).applying(backTransform)
        let renderSize = CGSize(width: abs(backRect.width).rounded(), height: abs(backRect.height).rounded())

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = PiPVideoCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = PiPInstruction(
            timeRange: CMTimeRange(start: .zero, duration: backDuration),
            backTrackID: compBack.trackID,
            frontTrackID: compFront.trackID,
            backOrientation: orientation(for: backTransform),
            frontOrientation: orientation(for: frontTransform)
        )
        videoComposition.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CompositeError.exportFailed
        }
        export.videoComposition = videoComposition
        let outputURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)_pip.mov")
        try await export.export(to: outputURL, as: .mov)
        return outputURL
    }

    /// Maps a track's preferred transform to the EXIF orientation CIImage
    /// understands (`oriented(_:)` also normalizes the extent origin).
    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0 { return .right }
        if transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0 { return .left }
        if transform.a == -1 && transform.d == -1 { return .down }
        return .up
    }
}

/// Per-frame instruction: which composition tracks feed the PiP and how each
/// is oriented. Immutable, so safe to hand across AVFoundation's queues.
nonisolated final class PiPInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let backTrackID: CMPersistentTrackID
    let frontTrackID: CMPersistentTrackID
    let backOrientation: CGImagePropertyOrientation
    let frontOrientation: CGImagePropertyOrientation

    init(
        timeRange: CMTimeRange,
        backTrackID: CMPersistentTrackID,
        frontTrackID: CMPersistentTrackID,
        backOrientation: CGImagePropertyOrientation,
        frontOrientation: CGImagePropertyOrientation
    ) {
        self.timeRange = timeRange
        self.backTrackID = backTrackID
        self.frontTrackID = frontTrackID
        self.backOrientation = backOrientation
        self.frontOrientation = frontOrientation
        self.requiredSourceTrackIDs = [
            NSNumber(value: backTrackID),
            NSNumber(value: frontTrackID),
        ]
    }
}

/// CoreImage compositor: rounded-corner PiP can't be expressed with plain
/// layer instructions, and the CoreAnimation tool can't reposition video
/// tracks. Callbacks arrive on AVFoundation queues — no main-actor touches.
nonisolated final class PiPVideoCompositor: NSObject, AVVideoCompositing {
    // Metal-backed and documented thread-safe; shared across requests.
    nonisolated(unsafe) private static let ciContext = CIContext()

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? PiPInstruction,
              let backBuffer = request.sourceFrame(byTrackID: instruction.backTrackID) else {
            request.finish(with: VideoCompositor.CompositeError.missingVideoTrack)
            return
        }

        let renderSize = request.renderContext.size
        var back = CIImage(cvPixelBuffer: backBuffer).oriented(instruction.backOrientation)
        if back.extent.size != renderSize, back.extent.width > 0, back.extent.height > 0 {
            back = back.transformed(by: CGAffineTransform(
                scaleX: renderSize.width / back.extent.width,
                y: renderSize.height / back.extent.height
            ))
        }

        var output = back
        if let frontBuffer = request.sourceFrame(byTrackID: instruction.frontTrackID) {
            var front = CIImage(cvPixelBuffer: frontBuffer).oriented(instruction.frontOrientation)
            // Mirror horizontally so the PiP matches what the user saw in the
            // (mirrored) front preview.
            front = front.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: front.extent.width, ty: 0))

            let pipWidth = renderSize.width * VideoCompositor.Layout.widthFraction
            let scale = pipWidth / front.extent.width
            front = front.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            let margin = renderSize.width * VideoCompositor.Layout.margin
            // CoreImage origin is bottom-left; top-trailing means high x and y.
            let origin = CGPoint(
                x: renderSize.width - front.extent.width - margin,
                y: renderSize.height - front.extent.height - margin
            )
            front = front.transformed(by: CGAffineTransform(translationX: origin.x - front.extent.origin.x,
                                                            y: origin.y - front.extent.origin.y))

            let rounded = CIFilter.roundedRectangleGenerator()
            rounded.extent = front.extent
            rounded.radius = Float(front.extent.width * VideoCompositor.Layout.cornerRadiusFraction)
            rounded.color = .white

            let blend = CIFilter.blendWithMask()
            blend.inputImage = front
            blend.backgroundImage = back
            blend.maskImage = rounded.outputImage
            output = blend.outputImage ?? back
        }

        guard let outBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: VideoCompositor.CompositeError.exportFailed)
            return
        }
        Self.ciContext.render(
            output,
            to: outBuffer,
            bounds: CGRect(origin: .zero, size: renderSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        request.finish(withComposedVideoFrame: outBuffer)
    }
}
