import Foundation
import Testing
@testable import KaraPitchTV

struct BackgroundKeyTests {
    private static let width = 64, height = 36

    /// A frame of `fill`, with `paint` deciding any pixel's color instead.
    private static func frame(_ fill: [UInt8], paint: (Int, Int) -> [UInt8]? = { _, _ in nil }) -> [UInt8] {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width { pixels += (paint(x, y) ?? fill) + [255] }
        }
        return pixels
    }

    @Test func findsAFlatBlueBehindWhiteLyrics() {
        // Lyrics across the middle third, plus a little compression noise in the blue.
        let pixels = Self.frame([20, 40, 200]) { x, y in
            if (12..<24).contains(y) && x % 3 != 0 { return [255, 255, 255] }
            return (x + y) % 5 == 0 ? [22, 41, 197] : nil
        }
        guard case let .keyed(color) = BackgroundKey.sample(pixels: pixels, width: Self.width, height: Self.height) else {
            Issue.record("expected a keyed background")
            return
        }
        #expect(color.distance(to: KeyColor(r: 20 / 255, g: 40 / 255, b: 200 / 255)) < 0.02)
        let share = BackgroundKey.dominant(pixels: pixels, width: Self.width, height: Self.height)?.share ?? 0
        #expect(share >= BackgroundKey.minShare)
    }

    @Test func keepsANoisyFrameOpaque() {
        var rng = SystemRandomNumberGenerator()
        let pixels = Self.frame([0, 0, 0]) { _, _ in (0..<3).map { _ in UInt8.random(in: 0...255, using: &rng) } }
        #expect(BackgroundKey.sample(pixels: pixels, width: Self.width, height: Self.height) == .opaque)
    }

    @Test func keysOutOnlyColorsNearTheKey() {
        let blue = KeyColor(r: 0.08, g: 0.16, b: 0.8)
        #expect(BackgroundKey.alpha(of: blue, key: blue) == 0)
        #expect(BackgroundKey.alpha(of: KeyColor(r: 0.1, g: 0.17, b: 0.78), key: blue) == 0)
        #expect(BackgroundKey.alpha(of: KeyColor(r: 1, g: 1, b: 1), key: blue) == 1)
        #expect(BackgroundKey.alpha(of: KeyColor(r: 0, g: 0, b: 0), key: blue) == 1)
    }

    @Test func buildsAPremultipliedCube() {
        let size = 4
        let data = BackgroundKey.cubeData(for: KeyColor(r: 0, g: 0, b: 1), size: size)
        let cube = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(cube.count == size * size * size * 4)
        // Pure blue (r 0, g 0, b last) is keyed out; white (the last entry) stays.
        let blue = (size - 1) * size * size * 4
        #expect(cube[blue + 3] == 0)
        #expect(Array(cube.suffix(4)) == [1, 1, 1, 1])
    }
}
