import Foundation

/// An sRGB color with components in 0...1.
struct KeyColor: Equatable, Sendable {
    var r: Float
    var g: Float
    var b: Float

    func distance(to other: KeyColor) -> Float {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

/// What a karaoke video's background turned out to be. Each video is sampled once, `sampleAt`
/// into the song, and keeps that answer to the end.
enum BackgroundSample: Equatable, Sendable {
    /// Not sampled yet: the video draws opaque.
    case pending
    /// A flat background in this color, keyed out so the backdrop shows through.
    case keyed(KeyColor)
    /// No color covers enough of the frame (a music video, say): the video stays opaque.
    case opaque
}

/// Finds a karaoke video's flat background color and builds the color cube that keys it out.
enum BackgroundKey {
    /// Far enough in to skip the black fade-in or title card most karaoke uploads open with.
    static let sampleAt = 5.0
    /// The sample frame's size; plenty to find a flat background.
    static let sampleWidth = 64
    static let sampleHeight = 36
    /// The share of the frame the dominant color must cover to count as the background.
    static let minShare = 0.35
    /// Pixels this close to the bucket's mean count toward it, so a color that straddles a bucket
    /// edge (or carries compression noise) isn't split in two.
    static let sameColor: Float = 0.1
    /// Fully transparent within `inner` of the key color, fully opaque past `outer`, smooth between.
    static let inner: Float = 0.12
    static let outer: Float = 0.24
    static let cubeSize = 32

    /// The background a sample frame shows: its dominant color, if that covers `minShare`.
    static func sample(pixels: [UInt8], width: Int, height: Int) -> BackgroundSample {
        guard let (color, share) = dominant(pixels: pixels, width: width, height: height), share >= minShare else { return .opaque }
        return .keyed(color)
    }

    /// The most common color in an RGBA8 frame and the share of pixels near it.
    static func dominant(pixels: [UInt8], width: Int, height: Int) -> (color: KeyColor, share: Double)? {
        let count = width * height
        guard count > 0, pixels.count >= count * 4 else { return nil }
        func color(at i: Int) -> KeyColor {
            KeyColor(r: Float(pixels[i * 4]) / 255, g: Float(pixels[i * 4 + 1]) / 255, b: Float(pixels[i * 4 + 2]) / 255)
        }

        // Most common 4-bit-per-channel bucket.
        var buckets = [Int](repeating: 0, count: 4096)
        func bucket(_ i: Int) -> Int { Int(pixels[i * 4] >> 4) << 8 | Int(pixels[i * 4 + 1] >> 4) << 4 | Int(pixels[i * 4 + 2] >> 4) }
        for i in 0..<count { buckets[bucket(i)] += 1 }
        guard let top = buckets.indices.max(by: { buckets[$0] < buckets[$1] }) else { return nil }

        // Its mean color, then every pixel near that mean.
        var sum = KeyColor(r: 0, g: 0, b: 0)
        var inTop = 0
        for i in 0..<count where bucket(i) == top {
            let c = color(at: i)
            sum.r += c.r
            sum.g += c.g
            sum.b += c.b
            inTop += 1
        }
        let mean = KeyColor(r: sum.r / Float(inTop), g: sum.g / Float(inTop), b: sum.b / Float(inTop))
        let near = (0..<count).filter { color(at: $0).distance(to: mean) <= sameColor }.count
        return (mean, Double(near) / Double(count))
    }

    /// How opaque a pixel of `color` is once `key` is keyed out.
    static func alpha(of color: KeyColor, key: KeyColor) -> Float {
        let t = min(max((color.distance(to: key) - inner) / (outer - inner), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Data for `CIColorCubeWithColorSpace`: premultiplied RGBA floats, red varying fastest.
    static func cubeData(for key: KeyColor, size: Int = cubeSize) -> Data {
        var cube = [Float]()
        cube.reserveCapacity(size * size * size * 4)
        let step = 1 / Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let color = KeyColor(r: Float(r) * step, g: Float(g) * step, b: Float(b) * step)
                    let a = alpha(of: color, key: key)
                    cube += [color.r * a, color.g * a, color.b * a, a]
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
