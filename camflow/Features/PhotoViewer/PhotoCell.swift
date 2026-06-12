import SwiftUI

/// Square thumbnail cell for photo grids, with an annotation badge.
struct PhotoCell: View {
    let photo: Photo

    @State private var thumbnail: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.fill.tertiary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if photo.annotationData != nil {
                    Image(systemName: "pencil.tip")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if photo.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        if let duration = photo.formattedDuration {
                            Text(duration)
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(4)
                }
            }
            .task(id: photo.thumbnailFileName) {
                let fileName = photo.thumbnailFileName
                thumbnail = await Task.detached {
                    FileStorage.load(fileName, in: .photos).flatMap(UIImage.init(data:))
                }.value
            }
    }
}
