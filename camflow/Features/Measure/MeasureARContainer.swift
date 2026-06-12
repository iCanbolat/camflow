import ARKit
import Combine
import RealityKit
import SwiftUI

/// Shared state between the AR coordinator and the SwiftUI overlay: completed
/// segments, the live (open) segment, and screen-projected label positions
/// refreshed every frame.
@MainActor
@Observable
final class MeasureSession {
    struct SegmentDisplay: Identifiable {
        let id = UUID()
        var segment: MeasurementSegment
        var labelPosition: CGPoint?
    }

    var segments: [SegmentDisplay] = []
    var pendingStart: SIMD3<Float>?
    var liveDistanceMeters: Double?
    var liveLabelPosition: CGPoint?
    var canPlacePoint = false
    var viewSize: CGSize = .zero

    var totalMeters: Double { segments.reduce(0) { $0 + $1.segment.distanceMeters } }
    var hasOpenSegment: Bool { pendingStart != nil }
}

/// Bridges SwiftUI buttons to the AR coordinator created inside the
/// representable.
@MainActor
final class MeasureController {
    weak var coordinator: MeasureARContainer.Coordinator?

    func addPoint() {
        coordinator?.addPoint()
    }

    func undo() {
        coordinator?.undo()
    }

    func snapshot(_ completion: @escaping @MainActor (UIImage?) -> Void) {
        if let coordinator {
            coordinator.snapshot(completion)
        } else {
            completion(nil)
        }
    }
}

/// Drives the ARView: center-reticle raycasts, sphere/line entities, and
/// per-frame label projection. ARKit and RealityKit deliver their callbacks
/// on the main thread, so the whole coordinator stays MainActor.
struct MeasureARContainer: UIViewRepresentable {
    let session: MeasureSession
    let controller: MeasureController

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // LiDAR devices raycast against real geometry for better accuracy;
        // non-LiDAR AR devices keep working on detected planes.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        arView.session.run(config)

        // Without coaching, users place points before tracking settles and get
        // garbage distances.
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: arView.topAnchor),
            coaching.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            coaching.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
        ])

        context.coordinator.attach(arView: arView)
        controller.coordinator = context.coordinator
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    @MainActor
    final class Coordinator {
        private let session: MeasureSession
        private weak var arView: ARView?
        private let rootAnchor = AnchorEntity(world: .zero)
        private var updateSubscription: (any Cancellable)?
        private var pendingSphere: ModelEntity?
        private var liveLine: ModelEntity?
        /// Entities per completed segment (start/end spheres + line) for undo.
        private var segmentEntities: [[Entity]] = []

        init(session: MeasureSession) {
            self.session = session
        }

        func attach(arView: ARView) {
            self.arView = arView
            arView.scene.addAnchor(rootAnchor)
            updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                self?.tick()
            }
        }

        /// Per-frame: refresh reticle hit state, the live segment, and all
        /// projected label positions.
        private func tick() {
            guard let arView else { return }
            session.viewSize = arView.bounds.size
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let hit = raycast(from: center)
            session.canPlacePoint = hit != nil

            if let start = session.pendingStart, let hit {
                updateLiveLine(from: start, to: hit)
                session.liveDistanceMeters = Double(simd_distance(start, hit))
                session.liveLabelPosition = arView.project((start + hit) / 2)
            }

            for index in session.segments.indices {
                let segment = session.segments[index].segment
                session.segments[index].labelPosition = arView.project((segment.start + segment.end) / 2)
            }
        }

        /// Center raycast with the fallback chain: detected plane geometry
        /// first, estimated planes otherwise.
        private func raycast(from point: CGPoint) -> SIMD3<Float>? {
            guard let arView else { return nil }
            let result = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any).first
                ?? arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first
            guard let result else { return nil }
            let column = result.worldTransform.columns.3
            return SIMD3(column.x, column.y, column.z)
        }

        func addPoint() {
            guard let arView else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let position = raycast(from: center) else { return }

            if let start = session.pendingStart {
                let endSphere = makeSphere(at: position)
                let line = makeLine(from: start, to: position)
                rootAnchor.addChild(endSphere)
                rootAnchor.addChild(line)

                var entities: [Entity] = [endSphere, line]
                if let pendingSphere {
                    entities.append(pendingSphere)
                }
                segmentEntities.append(entities)
                session.segments.append(.init(segment: MeasurementSegment(start: start, end: position)))

                pendingSphere = nil
                clearOpenSegment()
            } else {
                let sphere = makeSphere(at: position)
                rootAnchor.addChild(sphere)
                pendingSphere = sphere
                session.pendingStart = position
            }
        }

        func undo() {
            if session.pendingStart != nil {
                pendingSphere?.removeFromParent()
                pendingSphere = nil
                clearOpenSegment()
            } else if !session.segments.isEmpty {
                session.segments.removeLast()
                segmentEntities.popLast()?.forEach { $0.removeFromParent() }
            }
        }

        func snapshot(_ completion: @escaping @MainActor (UIImage?) -> Void) {
            guard let arView else {
                completion(nil)
                return
            }
            arView.snapshot(saveToHDR: false) { image in
                Task { @MainActor in completion(image) }
            }
        }

        private func clearOpenSegment() {
            session.pendingStart = nil
            session.liveDistanceMeters = nil
            session.liveLabelPosition = nil
            liveLine?.removeFromParent()
            liveLine = nil
        }

        private func makeSphere(at position: SIMD3<Float>) -> ModelEntity {
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.007),
                materials: [UnlitMaterial(color: .white)]
            )
            sphere.position = position
            return sphere
        }

        /// Unit-length box scaled along z — same trick the live line uses so
        /// its transform can be updated every frame without re-meshing.
        private func makeLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> ModelEntity {
            let line = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.004, 0.004, 1)),
                materials: [UnlitMaterial(color: .systemYellow)]
            )
            position(line, from: start, to: end)
            return line
        }

        private func updateLiveLine(from start: SIMD3<Float>, to end: SIMD3<Float>) {
            let line: ModelEntity
            if let liveLine {
                line = liveLine
            } else {
                line = ModelEntity(
                    mesh: .generateBox(size: SIMD3<Float>(0.004, 0.004, 1)),
                    materials: [UnlitMaterial(color: .systemYellow)]
                )
                rootAnchor.addChild(line)
                liveLine = line
            }
            position(line, from: start, to: end)
        }

        private func position(_ line: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
            let midpoint = (start + end) / 2
            line.look(at: end, from: midpoint, relativeTo: nil)
            line.scale = SIMD3<Float>(1, 1, simd_distance(start, end))
        }
    }
}
