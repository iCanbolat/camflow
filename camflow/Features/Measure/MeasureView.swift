import SwiftUI
import ARKit
import CoreLocation

/// Apple Measure-style AR point-to-point measuring. Capture saves the ARView
/// snapshot (labels baked in) as a project Photo plus a Measurement record.
struct MeasureView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService

    @AppStorage("measureUnit") private var unitRaw = Measurement.Unit.meters.rawValue

    @State private var session = MeasureSession()
    @State private var controller = MeasureController()
    @State private var isSaving = false

    private var unit: Measurement.Unit {
        Measurement.Unit(rawValue: unitRaw) ?? .meters
    }

    var body: some View {
        ZStack {
            MeasureARContainer(session: session, controller: controller)
                .ignoresSafeArea()

            labelOverlay

            reticle

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden()
    }

    // MARK: - Overlays

    /// Distance labels are SwiftUI views projected from world space — crisper
    /// than 3D text and trivially restyled. They are not part of the ARView
    /// snapshot, so capture() re-bakes them into the saved image.
    private var labelOverlay: some View {
        ZStack {
            ForEach(session.segments) { display in
                if let position = display.labelPosition {
                    distanceLabel(Measurement.format(meters: display.segment.distanceMeters, in: unit))
                        .position(position)
                }
            }
            if let liveDistance = session.liveDistanceMeters, let position = session.liveLabelPosition {
                distanceLabel(Measurement.format(meters: liveDistance, in: unit))
                    .position(position)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func distanceLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.65), in: Capsule())
    }

    private var reticle: some View {
        ZStack {
            Circle()
                .stroke(session.canPlacePoint ? AnyShapeStyle(.white) : AnyShapeStyle(.red.opacity(0.7)), lineWidth: 2)
                .frame(width: 28, height: 28)
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.4), in: Circle())
            }

            Spacer()

            if session.totalMeters > 0 {
                Text("Total: \(Measurement.format(meters: session.totalMeters, in: unit))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.4), in: Capsule())
            }

            Spacer()

            Button {
                unitRaw = unit == .meters ? Measurement.Unit.feet.rawValue : Measurement.Unit.meters.rawValue
            } label: {
                Text(unit == .meters ? "m" : "ft")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .disabled(session.segments.isEmpty && !session.hasOpenSegment)
            .opacity(session.segments.isEmpty && !session.hasOpenSegment ? 0.4 : 1)

            Spacer()

            Button {
                controller.addPoint()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
            }
            .disabled(!session.canPlacePoint)
            .opacity(session.canPlacePoint ? 1 : 0.4)

            Spacer()

            Button {
                capture()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 56, height: 56)
                        .background(.black.opacity(0.4), in: Circle())
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
            .disabled(session.segments.isEmpty || isSaving)
            .opacity(session.segments.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    // MARK: - Capture

    /// ARView snapshots include camera + RealityKit entities but not the
    /// SwiftUI label overlay — freeze the current label positions, bake them
    /// into the image off-main, then save photo + measurement.
    private func capture() {
        guard !isSaving else { return }
        isSaving = true

        let labels = session.segments.compactMap { display -> MeasureSnapshotRenderer.Label? in
            guard let position = display.labelPosition else { return nil }
            return .init(
                text: Measurement.format(meters: display.segment.distanceMeters, in: unit),
                position: position
            )
        }
        let totalText = "Total: \(Measurement.format(meters: session.totalMeters, in: unit))"
        let segments = session.segments.map(\.segment)
        let viewSize = session.viewSize
        let currentUnit = unit
        let location = locationService.lastKnownLocation

        controller.snapshot { image in
            guard let image else {
                isSaving = false
                return
            }
            Task {
                let data = await Task.detached {
                    MeasureSnapshotRenderer.render(image: image, viewSize: viewSize, labels: labels, totalText: totalText)
                }.value
                guard let data else {
                    isSaving = false
                    return
                }
                do {
                    let photo = try await PhotoStore(context: modelContext).createPhoto(
                        imageData: data,
                        latitude: location?.coordinate.latitude,
                        longitude: location?.coordinate.longitude,
                        source: .camera,
                        project: project
                    )
                    MeasurementStore(context: modelContext).create(
                        segments: segments,
                        unit: currentUnit,
                        snapshotPhotoID: photo.id,
                        project: project
                    )
                    dismiss()
                } catch {
                    isSaving = false
                }
            }
        }
    }
}

/// Bakes the SwiftUI distance labels + a total banner onto the ARView
/// snapshot — same composite trick as PhotoExporter's watermark bar.
nonisolated enum MeasureSnapshotRenderer {
    struct Label: Sendable {
        var text: String
        var position: CGPoint
    }

    static func render(image: UIImage, viewSize: CGSize, labels: [Label], totalText: String) -> Data? {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return image.jpegData(compressionQuality: 0.9)
        }
        let scale = image.size.width / viewSize.width
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let result = renderer.image { _ in
            image.draw(at: .zero)

            let labelFont = UIFont.monospacedDigitSystemFont(ofSize: 13 * scale, weight: .semibold)
            for label in labels {
                draw(
                    text: label.text,
                    font: labelFont,
                    center: CGPoint(x: label.position.x * scale, y: label.position.y * scale),
                    padding: CGSize(width: 8 * scale, height: 4 * scale)
                )
            }

            let bannerFont = UIFont.monospacedDigitSystemFont(ofSize: 17 * scale, weight: .bold)
            draw(
                text: totalText,
                font: bannerFont,
                center: CGPoint(x: image.size.width / 2, y: image.size.height - 40 * scale),
                padding: CGSize(width: 14 * scale, height: 8 * scale)
            )
        }
        return result.jpegData(compressionQuality: 0.9)
    }

    private static func draw(text: String, font: UIFont, center: CGPoint, padding: CGSize) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let background = CGRect(
            x: center.x - textSize.width / 2 - padding.width,
            y: center.y - textSize.height / 2 - padding.height,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        let path = UIBezierPath(roundedRect: background, cornerRadius: background.height / 2)
        UIColor.black.withAlphaComponent(0.65).setFill()
        path.fill()
        attributed.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2))
    }
}
