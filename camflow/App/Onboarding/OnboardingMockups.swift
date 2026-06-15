import SwiftUI

// Floating, layered "mockups" of CamFlow's real screens, shown as the hero of each
// onboarding slide instead of a flat SF Symbol. These are pure decoration built from
// shapes — no real data, no SwiftData — mirroring the styling of the actual components
// (PhotoCell, LabelChip, HomeView's kpiTile, MemberAvatar, the capture shutter) so the
// carousel reads as the genuine product. Sample copy uses `Text(verbatim:)` so it never
// reaches the string catalog. Each `body` stays small (composed of `private var`
// subviews) to avoid the SwiftUI type-checker blowing up on large expressions.

// MARK: - Shared mock primitives

/// Muted gradient fills standing in for jobsite photos.
private enum MockPalette {
    static func gradient(_ index: Int) -> LinearGradient {
        let hue = Double((index * 53 + 24) % 360) / 360
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.30, brightness: 0.82),
                Color(hue: hue, saturation: 0.46, brightness: 0.52),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Placeholder photo tile — caller sizes it. Mirrors `PhotoCell`'s rounded thumbnail.
private struct MockPhotoTile: View {
    var index: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MockPalette.gradient(index))
    }
}

/// Mirrors `LabelChip`.
private struct MockChip: View {
    var text: String
    var hex: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: hex).opacity(0.18), in: Capsule())
            .foregroundStyle(Color(hex: hex))
    }
}

/// Mirrors HomeView's `kpiTile`, shrunk for the mock.
private struct MockKPITile: View {
    var systemImage: String
    var value: String
    var label: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(verbatim: value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(verbatim: label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Mirrors `MemberAvatar`.
private struct MockAvatar: View {
    var initials: String
    var hex: String
    var size: CGFloat = 24

    var body: some View {
        Circle()
            .fill(Color(hex: hex).gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(verbatim: initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Reusable soft drop shadow + slight tilt for the floating-card look.
private extension View {
    func floatingCard(radius: CGFloat = 16, y: CGFloat = 10, tilt: Double = 0) -> some View {
        self
            .shadow(color: .black.opacity(0.16), radius: radius, y: y)
            .rotationEffect(.degrees(tilt))
    }
}

// MARK: - Capture

/// A camera viewfinder with project pill, focus reticle and the concentric shutter
/// (mirrors `CaptureView`'s shutter), with a freshly-captured photo floating in front.
struct CaptureMock: View {
    var body: some View {
        viewfinder
            .overlay(alignment: .bottomLeading) { floatingThumb }
    }

    private var viewfinder: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            shutterRow
        }
        .padding(16)
        .frame(width: 220, height: 300)
        .background(viewfinderFill, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .overlay { reticle }
        .floatingCard(radius: 22, y: 14, tilt: -2)
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill").font(.system(size: 10))
                Text(verbatim: "Riverside Tower").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.18), in: Capsule())
            Spacer()
            circleControl("bolt.fill")
        }
    }

    private var shutterRow: some View {
        HStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                }
            Spacer()
            shutterButton
            Spacer()
            circleControl("arrow.triangle.2.circlepath")
        }
    }

    private var shutterButton: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 4).frame(width: 60, height: 60)
            Circle().fill(.white).frame(width: 48, height: 48)
        }
    }

    private var reticle: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
            .frame(width: 116, height: 116)
    }

    private func circleControl(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.white.opacity(0.18), in: Circle())
    }

    private var viewfinderFill: LinearGradient {
        LinearGradient(
            colors: [Color(white: 0.20), Color(white: 0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var floatingThumb: some View {
        MockPhotoTile(index: 4)
            .frame(width: 58, height: 58)
            .overlay(alignment: .bottomTrailing) {
                MockAvatar(initials: "AS", hex: "#1B98E0", size: 18)
                    .overlay { Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1) }
                    .padding(3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: 2)
            }
            .floatingCard(radius: 8, y: 4, tilt: -6)
            .offset(x: -22, y: 16)
    }
}

// MARK: - Organize

/// A miniature Home feed: a dashboard card (greeting + KPI tiles) with a project group
/// card (name + label chip + photo row) overlapping below it for depth.
struct OrganizeMock: View {
    var body: some View {
        ZStack(alignment: .top) {
            dashboardCard
                .offset(y: -4)
                .rotationEffect(.degrees(-2))
            projectCard
                .offset(y: 134)
                .rotationEffect(.degrees(2))
        }
        .frame(width: 260, height: 310)
    }

    private var dashboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Good morning, Sam").font(.subheadline.weight(.bold))
                Text(verbatim: "Saturday, June 14").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                MockKPITile(systemImage: "camera.fill", value: "12", label: "Photos", tint: Color(hex: "#FF6B35"))
                MockKPITile(systemImage: "checklist", value: "4", label: "Tasks", tint: Color(hex: "#1B98E0"))
                MockKPITile(systemImage: "exclamationmark.triangle.fill", value: "1", label: "Overdue", tint: Color(hex: "#E0475B"))
            }
        }
        .padding(14)
        .frame(width: 244)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .floatingCard(radius: 14, y: 8)
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(verbatim: "Riverside Tower").font(.subheadline.weight(.semibold))
                MockChip(text: "Framing", hex: "#2E933C")
                Spacer()
                Text(verbatim: "9").font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    MockPhotoTile(index: i).frame(width: 50, height: 50)
                }
            }
        }
        .padding(14)
        .frame(width: 244)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .floatingCard(radius: 18, y: 12)
    }
}

// MARK: - Share

/// A "paper" PDF report page (title + PDF badge, metadata, photo grid) with a small
/// before/after comparison tile floating in front.
struct ShareMock: View {
    var body: some View {
        pdfCard
            .overlay(alignment: .bottomTrailing) { beforeAfterTile }
    }

    private var pdfCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            metadata
            photoGrid
        }
        .padding(18)
        .frame(width: 232)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.black.opacity(0.06), lineWidth: 1)
        }
        .floatingCard(radius: 18, y: 12, tilt: -2)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Weekly Report")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(white: 0.10))
                Text(verbatim: "Riverside Tower")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.45))
            }
            Spacer()
            Text(verbatim: "PDF")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(hex: "#E0475B"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var metadata: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar").font(.system(size: 9))
            Text(verbatim: "Jun 14 · 12 photos").font(.caption2)
        }
        .foregroundStyle(Color(white: 0.45))
    }

    private var photoGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<6, id: \.self) { i in
                MockPhotoTile(index: i + 1).frame(height: 50)
            }
        }
    }

    private var beforeAfterTile: some View {
        HStack(spacing: 0) {
            Rectangle().fill(MockPalette.gradient(0))
            Rectangle().fill(MockPalette.gradient(7))
        }
        .frame(width: 88, height: 58)
        .overlay { Rectangle().fill(.white).frame(width: 2.5) }
        .overlay {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.45), in: Circle())
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.7), lineWidth: 2)
        }
        .floatingCard(radius: 8, y: 5, tilt: 6)
        .offset(x: 18, y: 20)
    }
}

#Preview("Onboarding mocks") {
    ScrollView {
        VStack(spacing: 56) {
            CaptureMock()
            OrganizeMock()
            ShareMock()
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }
    .background(AmbientGlowBackground(tint: Color(hex: "#1B98E0")))
}
