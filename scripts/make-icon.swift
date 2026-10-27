// Draws the tvOS app icon layers and Top Shelf images into the asset catalog.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import Foundation

let catalog = "KaraPitchTV/Assets.xcassets/App Icon & Top Shelf Image.brandassets"

// The app's palette (UI/Theme.swift).
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let background = rgb(0x0D0B14)
let deepPurple = rgb(0x2B1446)
let pink = rgb(0xFF4FA3)
let orange = rgb(0xFF9A3D)
let text = rgb(0xF4F1FA)

enum Layer { case back, middle, front }

func render(width: Int, height: Int, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(width), CGFloat(height))
    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    try! FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Fills the current path with the pink→orange accent, left to right across `rect`.
func fillAccent(_ ctx: CGContext, _ rect: CGRect) {
    ctx.saveGState()
    ctx.clip()
    ctx.drawLinearGradient(gradient([pink, orange]), start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()
}

func strokeAccent(_ ctx: CGContext, width: CGFloat, _ rect: CGRect) {
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    fillAccent(ctx, rect)
}

// MARK: - Layers, drawn around a center point with `s` = the canvas height (y grows upward).

func drawBack(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, center: CGPoint, s: CGFloat) {
    ctx.drawLinearGradient(gradient([deepPurple, background]), start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
    ctx.drawRadialGradient(
        gradient([rgb(0xFF4FA3, 0.45), rgb(0xFF4FA3, 0)]), startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.62,
        options: [])
    ctx.drawRadialGradient(
        gradient([rgb(0xFF9A3D, 0.18), rgb(0xFF9A3D, 0)]), startCenter: CGPoint(x: center.x + s * 0.35, y: center.y - s * 0.3),
        startRadius: 0, endCenter: CGPoint(x: center.x + s * 0.35, y: center.y - s * 0.3), endRadius: s * 0.5, options: [])
}

/// Sound waves either side of the mic, and the pitch arrows: up on the right, down on the left.
func drawMiddle(_ ctx: CGContext, center c: CGPoint, s: CGFloat) {
    let bounds = CGRect(x: c.x - s * 0.8, y: c.y - s * 0.5, width: s * 1.6, height: s)
    for (i, radius) in [s * 0.30, s * 0.42].enumerated() {
        let spread = CGFloat.pi / (i == 0 ? 4.2 : 4.8)
        for side in [0.0, CGFloat.pi] {
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: c.x, y: c.y + s * 0.05), radius: radius, startAngle: side - spread, endAngle: side + spread, clockwise: false)
            ctx.setAlpha(i == 0 ? 1 : 0.7)
            strokeAccent(ctx, width: s * 0.045, bounds)
        }
    }
    ctx.setAlpha(1)
    // ▲ upper right, ▼ lower left: the key goes up and down.
    func chevron(at p: CGPoint, up: Bool) {
        let d = s * 0.07
        ctx.beginPath()
        ctx.move(to: CGPoint(x: p.x - d, y: p.y + (up ? -d / 2 : d / 2)))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + (up ? d / 2 : -d / 2)))
        ctx.addLine(to: CGPoint(x: p.x + d, y: p.y + (up ? -d / 2 : d / 2)))
        strokeAccent(ctx, width: s * 0.04, bounds)
    }
    chevron(at: CGPoint(x: c.x + s * 0.56, y: c.y + s * 0.30), up: true)
    chevron(at: CGPoint(x: c.x + s * 0.56, y: c.y + s * 0.18), up: true)
    chevron(at: CGPoint(x: c.x - s * 0.56, y: c.y - s * 0.12), up: false)
    chevron(at: CGPoint(x: c.x - s * 0.56, y: c.y - s * 0.24), up: false)
}

/// A stage microphone: gradient head with a grille, a holder, a stem and a base.
func drawFront(_ ctx: CGContext, center c: CGPoint, s: CGFloat) {
    let headW = s * 0.26, headH = s * 0.40
    let head = CGRect(x: c.x - headW / 2, y: c.y - s * 0.02, width: headW, height: headH)

    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: rgb(0x000000, 0.5))
    ctx.beginPath()
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: headW / 2, cornerHeight: headW / 2, transform: nil))
    ctx.setFillColor(pink)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    ctx.addPath(CGPath(roundedRect: head, cornerWidth: headW / 2, cornerHeight: headW / 2, transform: nil))
    fillAccent(ctx, head)

    // Grille: horizontal slots across the head.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: head.insetBy(dx: headW * 0.18, dy: headW * 0.18), cornerWidth: headW * 0.32, cornerHeight: headW * 0.32, transform: nil))
    ctx.clip()
    ctx.setStrokeColor(rgb(0x0D0B14, 0.35))
    ctx.setLineWidth(s * 0.018)
    ctx.setLineCap(.round)
    var y = head.minY + headW * 0.3
    while y < head.maxY - headW * 0.25 {
        ctx.move(to: CGPoint(x: head.minX, y: y))
        ctx.addLine(to: CGPoint(x: head.maxX, y: y))
        y += s * 0.045
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Shine on the upper left.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: headW / 2, cornerHeight: headW / 2, transform: nil))
    ctx.clip()
    ctx.setFillColor(rgb(0xFFFFFF, 0.22))
    ctx.fillEllipse(in: CGRect(x: head.minX + headW * 0.12, y: head.maxY - headW * 0.75, width: headW * 0.3, height: headW * 0.55))
    ctx.restoreGState()

    // Holder, stem and base in the light text color.
    ctx.setStrokeColor(text)
    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.04)
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: c.x, y: head.minY + headW * 0.5), radius: headW * 0.78, startAngle: .pi * 1.02, endAngle: .pi * 1.98, clockwise: false)
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: CGPoint(x: c.x, y: head.minY + headW * 0.5 - headW * 0.78))
    ctx.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.30))
    ctx.move(to: CGPoint(x: c.x - s * 0.11, y: c.y - s * 0.30))
    ctx.addLine(to: CGPoint(x: c.x + s * 0.11, y: c.y - s * 0.30))
    ctx.strokePath()
}

func icon(_ layer: Layer, width: Int, height: Int) -> CGImage {
    render(width: width, height: height) { ctx, w, h in
        let c = CGPoint(x: w / 2, y: h / 2)
        switch layer {
        case .back: drawBack(ctx, w, h, center: c, s: h)
        case .middle: drawMiddle(ctx, center: c, s: h)
        case .front: drawFront(ctx, center: c, s: h)
        }
    }
}

/// A wide banner: the whole icon on the left, the name on the right.
func topShelf(width: Int, height: Int) -> CGImage {
    render(width: width, height: height) { ctx, w, h in
        let c = CGPoint(x: w * 0.3, y: h / 2)
        drawBack(ctx, w, h, center: c, s: h)
        drawMiddle(ctx, center: c, s: h * 0.9)
        drawFront(ctx, center: c, s: h * 0.9)
        let title = NSAttributedString(string: "Kara Pitch", attributes: [
            .font: NSFont.systemFont(ofSize: h * 0.2, weight: .black),
            .foregroundColor: NSColor(cgColor: text)!,
        ])
        let line = CTLineCreateWithAttributedString(title)
        ctx.textPosition = CGPoint(x: w * 0.52, y: h * 0.47)
        CTLineDraw(line, ctx)
        let tagline = NSAttributedString(string: "Karaoke in any key", attributes: [
            .font: NSFont.systemFont(ofSize: h * 0.075, weight: .semibold),
            .foregroundColor: NSColor(cgColor: orange)!,
        ])
        ctx.textPosition = CGPoint(x: w * 0.525, y: h * 0.33)
        CTLineDraw(CTLineCreateWithAttributedString(tagline), ctx)
    }
}

// MARK: - Asset catalog

let info: [String: Any] = ["author": "xcode", "version": 1]

func json(_ object: [String: Any], at dir: String) {
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: dir + "/Contents.json"))
}

func imageStack(_ name: String, size: (Int, Int), scales: [Int]) {
    let dir = "\(catalog)/\(name).imagestack"
    let layers: [(String, Layer)] = [("Front", .front), ("Middle", .middle), ("Back", .back)]
    json(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], at: dir)
    for (layerName, layer) in layers {
        let layerDir = "\(dir)/\(layerName).imagestacklayer"
        json(["info": info], at: layerDir)
        var images: [[String: Any]] = []
        for scale in scales {
            let file = "\(layerName.lowercased())\(scale > 1 ? "@\(scale)x" : "").png"
            write(icon(layer, width: size.0 * scale, height: size.1 * scale), to: "\(layerDir)/Content.imageset/\(file)")
            images.append(["idiom": "tv", "scale": "\(scale)x", "filename": file])
        }
        json(["images": images, "info": info], at: "\(layerDir)/Content.imageset")
    }
}

func imageSet(_ name: String, size: (Int, Int)) {
    let dir = "\(catalog)/\(name).imageset"
    var images: [[String: Any]] = []
    for scale in [1, 2] {
        let file = "top-shelf\(scale > 1 ? "@\(scale)x" : "").png"
        write(topShelf(width: size.0 * scale, height: size.1 * scale), to: "\(dir)/\(file)")
        images.append(["idiom": "tv", "scale": "\(scale)x", "filename": file])
    }
    json(["images": images, "info": info], at: dir)
}

try? FileManager.default.removeItem(atPath: catalog)
json(["info": info], at: "KaraPitchTV/Assets.xcassets")
json([
    "info": info,
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
], at: catalog)
imageStack("App Icon", size: (400, 240), scales: [1, 2])
imageStack("App Icon - App Store", size: (1280, 768), scales: [1])
imageSet("Top Shelf Image", size: (1920, 720))
imageSet("Top Shelf Image Wide", size: (2320, 720))

// A flattened preview to look at.
let preview = render(width: 1600, height: 960) { ctx, w, h in
    let c = CGPoint(x: w / 2, y: h / 2)
    drawBack(ctx, w, h, center: c, s: h)
    drawMiddle(ctx, center: c, s: h)
    drawFront(ctx, center: c, s: h)
}
write(preview, to: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon-preview.png")
print("wrote \(catalog)")
