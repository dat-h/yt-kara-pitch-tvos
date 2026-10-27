import AVFoundation
import CoreImage
import Metal
import UIKit
import os

/// Draws the karaoke video with its background color keyed out, so whatever is behind this view
/// shows through. `AVPlayerLayer` ignores alpha, so frames come from the player's video output and
/// go through Core Image into a transparent Metal layer.
final class KeyedVideoView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    private let player: KaraPlayer
    private let queue: (any MTLCommandQueue)?
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var displayLink: CADisplayLink?
    /// The filter for the key color in use, built once per keyed video.
    private var filter: (key: KeyColor, filter: CIFilter)?

    init(player: KaraPlayer) {
        self.player = player
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0) } ?? CIContext()
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false  // Core Image writes the texture directly
        metalLayer.isOpaque = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Set by the host: false while background video is off, so nothing is drawn.
    var isShown = false {
        didSet { updateRunning() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRunning()
    }

    /// Runs the display link only while shown and on screen; it retains this view until invalidated.
    private func updateRunning() {
        let run = isShown && window != nil
        guard run != (displayLink != nil) else { return }
        displayLink?.invalidate()
        displayLink = nil
        if run {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// Draws each new frame; the layer keeps showing the last one in between (and while paused).
    @objc private func tick() {
        guard let output = player.videoOutput else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
            let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        let frame = CIImage(cvPixelBuffer: buffer)
        sampleIfDue(frame, at: itemTime.seconds)
        draw(frame)
    }

    /// Takes the one sample of this video's background once playback reaches `sampleAt` (or near
    /// the end of a video shorter than that).
    private func sampleIfDue(_ image: CIImage, at seconds: Double) {
        guard player.background == .pending, seconds.isFinite else { return }
        let duration = player.player.currentItem?.duration.seconds ?? .infinity
        let due = min(BackgroundKey.sampleAt, duration.isFinite ? max(0, duration - 1) : .infinity)
        guard seconds >= due else { return }

        let (w, h) = (BackgroundKey.sampleWidth, BackgroundKey.sampleHeight)
        let extent = image.extent
        let small = image
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / extent.width, y: CGFloat(h) / extent.height))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        context.render(small, toBitmap: &pixels, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: colorSpace)
        player.setBackground(BackgroundKey.sample(pixels: pixels, width: w, height: h))
    }

    private func keyed(_ image: CIImage) -> CIImage {
        guard case let .keyed(key) = player.background else { return image }
        if filter?.key != key {
            let cube = CIFilter(name: "CIColorCubeWithColorSpace")!
            cube.setValue(BackgroundKey.cubeSize, forKey: "inputCubeDimension")
            cube.setValue(BackgroundKey.cubeData(for: key), forKey: "inputCubeData")
            cube.setValue(colorSpace, forKey: "inputColorSpace")
            filter = (key, cube)
        }
        guard let cube = filter?.filter else { return image }
        cube.setValue(image, forKey: kCIInputImageKey)
        return cube.outputImage ?? image
    }

    private func draw(_ frame: CIImage) {
        guard let queue, let drawable = metalLayer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let target = CGRect(origin: .zero, size: metalLayer.drawableSize)
        guard target.width > 0, target.height > 0 else { return }

        // Aspect-fit, centered, over transparent.
        let extent = frame.extent
        let scale = min(target.width / extent.width, target.height / extent.height)
        let fit = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(
            translationX: (target.width - extent.width * scale) / 2, y: (target.height - extent.height * scale) / 2))
        let image = keyed(frame).transformed(by: fit).composited(over: CIImage(color: .clear).cropped(to: target))

        context.render(image, to: drawable.texture, commandBuffer: commands, bounds: target, colorSpace: colorSpace)
        commands.present(drawable)
        commands.commit()
    }
}
