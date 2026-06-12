import SwiftUI
import SwiftData

/// Pre-share options: branded export toggle, then hands files to ShareLink.
/// Exports run eagerly so the share button is ready when tapped.
struct ShareOptionsSheet: View {
    let photos: [Photo]

    @Environment(\.modelContext) private var modelContext
    @Environment(Session.self) private var session
    @AppStorage("brandedExportDefault") private var branded = true

    @State private var exportedURLs: [URL] = []
    @State private var isExporting = false

    private var containsVideo: Bool {
        photos.contains(where: \.isVideo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Branded export", isOn: $branded)
                        .disabled(photos.allSatisfy(\.isVideo))
                } footer: {
                    if containsVideo {
                        Text("Adds your company logo, the capture time, and GPS coordinates. Annotations are always included. Videos are shared without branding.")
                    } else {
                        Text("Adds your company logo, the capture time, and GPS coordinates. Annotations are always included.")
                    }
                }

                Section {
                    if isExporting {
                        HStack {
                            ProgressView()
                            if containsVideo {
                                Text("Preparing ^[\(photos.count) item](inflect: true)…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Preparing ^[\(photos.count) photo](inflect: true)…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        ShareLink(items: exportedURLs) {
                            Group {
                                if containsVideo {
                                    Label("Share ^[\(exportedURLs.count) item](inflect: true)", systemImage: "square.and.arrow.up")
                                } else {
                                    Label("Share ^[\(exportedURLs.count) photo](inflect: true)", systemImage: "square.and.arrow.up")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(exportedURLs.isEmpty)
                    }
                }
            }
            .navigationTitle(containsVideo ? "Share Media" : "Share Photos")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: branded) { await prepareExports() }
        }
        .presentationDetents([.medium])
    }

    private func prepareExports() async {
        isExporting = true
        defer { isExporting = false }

        let organization = session.activeOrganization
        var urls: [URL] = []
        for photo in photos {
            if let url = await PhotoExporter.export(photo, branded: branded, organization: organization) {
                urls.append(url)
            }
        }
        exportedURLs = urls
    }
}
