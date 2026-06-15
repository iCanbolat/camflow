import SwiftUI

/// Marketing intro carousel shown once before sign-in. Each slide pairs a floating,
/// layered mock of the real screen it describes (see `OnboardingMockups`) with a soft
/// per-slide ambient glow (`AmbientGlowBackground`) that cross-fades as you swipe. The
/// overall app flow (slides → auth → org → permissions) is orchestrated by
/// `RootCoordinatorView`.
struct WelcomeView: View {
    var onContinue: () -> Void

    @State private var page = 0

    private enum Kind { case capture, organize, share }

    private struct Slide {
        let kind: Kind
        let tint: Color
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }

    private let slides: [Slide] = [
        .init(
            kind: .capture,
            tint: Color(hex: "#FF6B35"),
            title: "Capture",
            subtitle: "Take unlimited photos, automatically stamped with time and location."
        ),
        .init(
            kind: .organize,
            tint: Color(hex: "#1B98E0"),
            title: "Organize",
            subtitle: "Every photo lands in the right project — tagged, searchable, annotated."
        ),
        .init(
            kind: .share,
            tint: Color(hex: "#13B5B1"),
            title: "Share",
            subtitle: "Build professional PDF reports and before/after shots in minutes."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    slidePage(slides[index], isActive: page == index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            continueButton
        }
        .background {
            AmbientGlowBackground(tint: slides[page].tint)
                .animation(.easeInOut(duration: 0.6), value: page)
        }
    }

    private func slidePage(_ slide: Slide, isActive: Bool) -> some View {
        VStack(spacing: 28) {
            hero(for: slide.kind)
                .frame(height: 320)
                .scaleEffect(isActive ? 1 : 0.9)
                .opacity(isActive ? 1 : 0.45)
                .animation(.spring(response: 0.55, dampingFraction: 0.85), value: isActive)
                .phaseAnimator([-5.0, 5.0]) { view, offset in
                    view.offset(y: offset)
                } animation: { _ in
                    .easeInOut(duration: 2.4)
                }

            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.largeTitle.bold())
                Text(slide.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func hero(for kind: Kind) -> some View {
        switch kind {
        case .capture: CaptureMock()
        case .organize: OrganizeMock()
        case .share: ShareMock()
        }
    }

    private var continueButton: some View {
        Button {
            if page < slides.count - 1 {
                withAnimation { page += 1 }
            } else {
                onContinue()
            }
        } label: {
            Text(page < slides.count - 1 ? "Next" : "Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

#Preview {
    WelcomeView {}
}
