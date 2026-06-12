import SwiftUI

/// Read-only detail for a saved measurement: the snapshot photo (labels baked
/// in) plus per-segment distances in the measurement's unit.
struct MeasurementDetailSheet: View {
    let measurement: Measurement

    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: UIImage?

    var body: some View {
        NavigationStack {
            List {
                if let snapshot {
                    Section {
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFit()
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section("Segments") {
                    ForEach(Array(measurement.segments.enumerated()), id: \.offset) { index, segment in
                        LabeledContent("Segment \(index + 1)") {
                            Text(Measurement.format(meters: segment.distanceMeters, in: measurement.unit))
                                .monospacedDigit()
                        }
                    }
                }

                Section {
                    LabeledContent("Total") {
                        Text(Measurement.format(meters: measurement.totalMeters, in: measurement.unit))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    LabeledContent("Measured") {
                        Text(measurement.capturedAt, format: .dateTime.day().month().year().hour().minute())
                    }
                }
            }
            .navigationTitle("Measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard snapshot == nil,
                      let photoID = measurement.snapshotPhotoID,
                      let photo = measurement.project?.activePhotos.first(where: { $0.id == photoID }) else { return }
                let fileName = photo.fileName
                snapshot = await Task.detached {
                    FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
                }.value
            }
        }
    }
}
