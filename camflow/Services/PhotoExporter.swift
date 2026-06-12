import SwiftUI

/// Renders photos for sharing: annotations baked into pixels, with an
/// optional branded bar (logo, company name, timestamp, GPS).
@MainActor
enum PhotoExporter {
    struct Branding {
        var companyName: String
        var logo: UIImage?
        var capturedAt: Date
        var latitude: Double?
        var longitude: Double?
    }

    /// Exports to a temp file URL suitable for the share sheet.
    /// Videos skip branded rendering — the file is handed over as-is.
    static func export(_ photo: Photo, branded: Bool, organization: Organization?) async -> URL? {
        if photo.isVideo {
            return await exportVideo(photo)
        }

        let fileName = photo.fileName
        guard let image = await Task.detached(operation: {
            FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
        }).value else { return nil }

        let shapes = AnnotationDocument.decode(photo.annotationData).shapes

        var branding: Branding?
        if branded {
            let logo = organization?.logoFileName.flatMap { FileStorage.loadImage($0, in: .branding) }
            branding = Branding(
                companyName: organization?.name ?? "",
                logo: logo,
                capturedAt: photo.capturedAt,
                latitude: photo.latitude,
                longitude: photo.longitude
            )
        }

        let targetWidth = min(image.size.width * image.scale, 2048)
        let content = ExportPhotoView(image: image, shapes: shapes, branding: branding, targetWidth: targetWidth)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: targetWidth, height: nil)
        renderer.scale = 1

        guard let rendered = renderer.uiImage,
              let data = rendered.jpegData(compressionQuality: 0.9) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(tempBaseName(for: photo)).jpg")

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Stages a video under a friendly name for the share sheet. Hard link
    /// instead of copy — a 2-minute clip can be hundreds of MB.
    private static func exportVideo(_ photo: Photo) async -> URL? {
        let sourceURL = FileStorage.url(for: photo.fileName, in: .photos)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(tempBaseName(for: photo)).mov")

        return await Task.detached {
            let fm = FileManager.default
            try? fm.removeItem(at: url)
            do {
                try fm.linkItem(at: sourceURL, to: url)
                return url
            } catch {
                return (try? fm.copyItem(at: sourceURL, to: url)) != nil ? url : nil
            }
        }.value
    }

    private static func tempBaseName(for photo: Photo) -> String {
        let dateStamp = photo.capturedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
            .replacingOccurrences(of: "/", with: "-")
        let projectPart = (photo.project?.name ?? "CamFlow")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(projectPart)_\(dateStamp)_\(photo.id.uuidString.prefix(6))"
    }
}

/// The composition that gets rendered to pixels on export.
private struct ExportPhotoView: View {
    let image: UIImage
    let shapes: [AnnotationShape]
    let branding: PhotoExporter.Branding?
    let targetWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if !shapes.isEmpty {
                        Canvas { context, size in
                            AnnotationRenderer.draw(shapes, in: &context, size: size)
                        }
                    }
                }

            if let branding {
                brandingBar(branding)
            }
        }
    }

    private func brandingBar(_ branding: PhotoExporter.Branding) -> some View {
        let base = targetWidth * 0.022
        return HStack(spacing: base) {
            if let logo = branding.logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: base * 3.4, height: base * 3.4)
                    .clipShape(RoundedRectangle(cornerRadius: base * 0.5))
            }

            VStack(alignment: .leading, spacing: base * 0.25) {
                if !branding.companyName.isEmpty {
                    Text(branding.companyName)
                        .font(.system(size: base * 1.25, weight: .bold))
                }
                Text(timestampLine(branding))
                    .font(.system(size: base * 0.95))
                    .opacity(0.85)
            }

            Spacer()

            Text(verbatim: "CamFlow")
                .font(.system(size: base * 0.9, weight: .semibold))
                .opacity(0.5)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, base * 1.2)
        .padding(.vertical, base)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.9))
    }

    private func timestampLine(_ branding: PhotoExporter.Branding) -> String {
        var line = branding.capturedAt.formatted(date: .abbreviated, time: .shortened)
        if let lat = branding.latitude, let lon = branding.longitude {
            line += String(format: "  ·  %.4f, %.4f", lat, lon)
        }
        return line
    }
}
