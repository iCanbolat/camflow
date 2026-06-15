import SwiftUI

/// Soft, blurred ambient "light" wash. Two radial glows in `tint` — a primary
/// top-trailing and a softer bottom-leading — float over the grouped background,
/// tuned per appearance (a touch stronger on the dark base). A richer cousin of
/// HomeView's `ambientBackground`, reusable behind full-screen marketing/onboarding
/// content. Animate the `tint` from the caller to cross-fade between contexts.
struct AmbientGlowBackground: View {
    var tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            glow(alignment: .topTrailing, size: 380,
                 opacity: colorScheme == .dark ? 0.55 : 0.34)
            glow(alignment: .bottomLeading, size: 300,
                 opacity: colorScheme == .dark ? 0.30 : 0.16)
        }
        .ignoresSafeArea()
    }

    private func glow(alignment: Alignment, size: CGFloat, opacity: Double) -> some View {
        RadialGradient(
            colors: [tint.opacity(opacity), .clear],
            center: .center,
            startRadius: 0,
            endRadius: size / 2
        )
        .frame(width: size, height: size)
        .blur(radius: 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

#Preview {
    AmbientGlowBackground(tint: Color(hex: "#1B98E0"))
}
