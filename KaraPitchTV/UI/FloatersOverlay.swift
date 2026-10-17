import SwiftUI

/// The reaction emojis drifting up the screen. Half see-through at most, so lyrics behind them
/// stay readable, and never focusable or hit-testable.
struct FloatersOverlay: View {
    static let maxOpacity = 0.55
    static let rise: CGFloat = 220

    let floaters: [Floater]

    var body: some View {
        GeometryReader { geometry in
            ForEach(floaters) { floater in
                FloatingEmoji(floater: floater)
                    .position(x: floater.x * geometry.size.width, y: floater.y * geometry.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct FloatingEmoji: View {
    let floater: Floater
    /// Flipped on appear to start the keyframes. `repeating: false` would never play them, leaving
    /// the emoji on its first frame, which is fully transparent.
    @State private var started = false

    private struct Pose {
        var rise: CGFloat = 0
        var sway: CGFloat = 0
        var opacity = 0.0
        var scale = 0.6
    }

    var body: some View {
        let seconds = Double(Floater.lifetime.components.seconds) - floater.delay
        Text(floater.emoji)
            .font(.system(size: floater.size))
            .keyframeAnimator(initialValue: Pose(), trigger: started) { content, pose in
                content
                    .scaleEffect(pose.scale)
                    .opacity(pose.opacity)
                    .offset(x: pose.sway, y: -pose.rise)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: floater.delay)
                    LinearKeyframe(FloatersOverlay.maxOpacity, duration: 0.3)
                    LinearKeyframe(FloatersOverlay.maxOpacity, duration: max(0, seconds - 1.2))
                    LinearKeyframe(0, duration: 0.9)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.6, duration: floater.delay)
                    SpringKeyframe(1, duration: 0.4)
                }
                KeyframeTrack(\.rise) {
                    LinearKeyframe(0, duration: floater.delay)
                    CubicKeyframe(FloatersOverlay.rise, duration: seconds)
                }
                KeyframeTrack(\.sway) {
                    LinearKeyframe(0, duration: floater.delay)
                    CubicKeyframe(18, duration: seconds / 3)
                    CubicKeyframe(-18, duration: seconds / 3)
                    CubicKeyframe(0, duration: seconds / 3)
                }
            }
            .onAppear { started = true }
    }
}
