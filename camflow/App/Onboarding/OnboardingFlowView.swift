import SwiftUI
import SwiftData

/// Marketing intro carousel shown once before sign-in. The overall app flow
/// (slides → auth → org → permissions) is orchestrated by `RootCoordinatorView`.
struct WelcomeView: View {
    var onContinue: () -> Void

    @State private var page = 0

    private struct Slide {
        let systemImage: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }

    private let slides: [Slide] = [
        .init(
            systemImage: "camera.fill",
            title: "Capture",
            subtitle: "Take unlimited photos, automatically stamped with time and location."
        ),
        .init(
            systemImage: "folder.fill.badge.gearshape",
            title: "Organize",
            subtitle: "Every photo lands in the right project — tagged, searchable, annotated."
        ),
        .init(
            systemImage: "square.and.arrow.up.fill",
            title: "Share",
            subtitle: "Build professional PDF reports and before/after shots in minutes."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    VStack(spacing: 24) {
                        Image(systemName: slides[index].systemImage)
                            .font(.system(size: 72))
                            .foregroundStyle(.tint)
                        Text(slides[index].title)
                            .font(.largeTitle.bold())
                        Text(slides[index].subtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

#Preview {
    WelcomeView {}
}
