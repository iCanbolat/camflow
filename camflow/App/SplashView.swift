import SwiftUI

/// Animated launch splash: the brand mark bounces in over concentric orange "pulse"
/// rings that ripple outward, with a soft breathing halo. Sits on `systemBackground`
/// so it reads on every theme (light and dark). Overlaid on the app root by
/// `CamFlowApp` and faded out via `onFinished` after a short hold. Honors Reduce Motion.
struct SplashView: View {
    /// Called once the splash has finished its intro and is ready to dismiss.
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private let brand = Color(hex: "#FF6B35")

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            halo
            if !reduceMotion { pulseRings }
            logo
        }
        .task {
            // Hold long enough for the bounce + a couple of pulses, then hand off.
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.9 : 2.0))
            onFinished()
        }
    }

    // MARK: - Pieces

    /// Soft orange glow behind the mark; gently breathes when motion is allowed.
    private var halo: some View {
        RadialGradient(
            colors: [brand.opacity(0.35), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 130
        )
        .frame(width: 280, height: 280)
        .blur(radius: 30)
        .scaleEffect(breathe ? 1.12 : 0.92)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }

    /// Three staggered rings rippling outward like a sonar ping.
    private var pulseRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                PulseRing(brand: brand, delay: Double(i) * 0.7)
            }
        }
    }

    /// The brand mark, bouncing in from below with a secondary hop.
    @ViewBuilder
    private var logo: some View {
        let mark = Image("CamFlowIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 116, height: 116)

        if reduceMotion {
            mark
        } else {
            mark.keyframeAnimator(initialValue: LogoMotion()) { content, motion in
                content
                    .scaleEffect(motion.scale)
                    .offset(y: motion.yOffset)
                    .opacity(motion.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.25)
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.0, duration: 0.65, spring: .bouncy)
                }
                KeyframeTrack(\.yOffset) {
                    SpringKeyframe(0, duration: 0.50, spring: .snappy)   // rise & settle
                    CubicKeyframe(0, duration: 0.12)                     // beat
                    SpringKeyframe(-18, duration: 0.32, spring: .bouncy) // hop up
                    SpringKeyframe(0, duration: 0.42, spring: .bouncy)   // land
                }
            }
        }
    }
}

/// Animatable state for the logo's bounce-in.
private struct LogoMotion {
    var scale: CGFloat = 0.55
    var yOffset: CGFloat = 36
    var opacity: CGFloat = 0
}

/// A single orange ring that expands from the center and fades, looping forever.
private struct PulseRing: View {
    var brand: Color
    var delay: Double

    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(brand.opacity(0.55), lineWidth: 2.5)
            .frame(width: 116, height: 116)
            .scaleEffect(expanded ? 2.4 : 0.4)
            .opacity(expanded ? 0 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(delay)) {
                    expanded = true
                }
            }
    }
}

#Preview {
    SplashView {}
}
