import SwiftUI
import MapKit
import UIKit

/// A lightweight, non-interactive map preview rendered once via `MKMapSnapshotter`.
///
/// Embedding a live `Map` inside a `Form`/`List` row spins up a Metal layer,
/// gesture recognizers, and live tile loading on first appearance — a noticeable
/// hitch on device, and the source of the `CAMetalLayer ... setDrawableSize 0x0`
/// / "System gesture gate timed out" console noise. Since the project map only
/// needs to *show* a fixed location, a static snapshot image is far cheaper and
/// renders without that cost.
///
/// The marker is drawn in SwiftUI at the view's center, which is exact because
/// the snapshot region is centered on `coordinate`.
struct MapSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    var spanMeters: CLLocationDistance = 600

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    @State private var snapshot: Image?
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            if let snapshot {
                snapshot
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.fill.tertiary)
                    .overlay { ProgressView() }
            }
        }
        .overlay {
            if snapshot != nil {
                Image(systemName: "mappin.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .shadow(radius: 1)
                    .accessibilityHidden(true)
            }
        }
        .clipped()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: snapshotKey) { await renderSnapshot() }
        .accessibilityElement()
        .accessibilityLabel(Text("Map showing \(title)"))
    }

    private var snapshotKey: String {
        "\(coordinate.latitude),\(coordinate.longitude),\(Int(size.width)),\(Int(size.height)),\(colorScheme == .dark)"
    }

    private func renderSnapshot() async {
        guard size.width > 0, size.height > 0 else { return }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        )
        options.size = size
        options.scale = displayScale
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: colorScheme == .dark ? .dark : .light
        )

        let snapshotter = MKMapSnapshotter(options: options)
        guard let result = try? await snapshotter.start() else { return }
        snapshot = Image(uiImage: result.image)
    }
}
