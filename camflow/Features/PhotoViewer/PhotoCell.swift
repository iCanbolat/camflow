import SwiftUI

/// Square thumbnail cell for photo grids, with an annotation badge. Loads via
/// `MediaProvider` (local file first, else a downloaded CDN thumbnail). When no
/// bytes are available yet, the placeholder reflects the server processing state.
struct PhotoCell: View {
    let photo: Photo
    var showAuthor: Bool = true

    @Environment(AppServices.self) private var services
    @State private var thumbnail: UIImage?
    @State private var didLoad = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
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
            .overlay(alignment: .topLeading) {
                verificationBadge
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
            .overlay(alignment: .bottomTrailing) {
                if showAuthor, let author = photo.author {
                    MemberAvatar(member: author, size: 20)
                        .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                        .padding(4)
                }
            }
            .task(id: photo.id) {
                didLoad = false
                let ref = MediaProvider.Ref(photo, organizationID: nil)
                thumbnail = await services.mediaProvider.image(for: ref, variant: .thumbnail)
                didLoad = true
            }
    }

    /// No bytes (yet): show a loading spinner while fetching, a failed badge when
    /// the server pipeline failed, or a neutral photo glyph.
    @ViewBuilder
    private var placeholder: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if photo.processingStatus == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if !didLoad || isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: photo.isVideo ? "video" : "photo")
                        .foregroundStyle(.tertiary)
                }
            }
    }

    private var isProcessing: Bool {
        switch photo.processingStatus {
        case .pending, .queued, .processing: true
        case .done, .failed: false
        }
    }

    /// Location/time trust seal. Only the loud states show in the grid (a ✓ for a
    /// verified stamp, a ⚠ for a flagged one); `unverified` stays uncluttered.
    @ViewBuilder
    private var verificationBadge: some View {
        switch photo.captureVerification {
        case .verified:
            Image(systemName: "checkmark.seal.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white, .green)
                .padding(4)
                .background(.black.opacity(0.4), in: Circle())
                .padding(4)
        case .flagged:
            Image(systemName: "exclamationmark.shield.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white, .red)
                .padding(4)
                .background(.black.opacity(0.4), in: Circle())
                .padding(4)
        case .unverified:
            EmptyView()
        }
    }
}
