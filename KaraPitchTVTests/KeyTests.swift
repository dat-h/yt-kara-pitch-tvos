import Testing
@testable import KaraPitchTV

/// Ported from the Android app's `KeyTest.kt`.
struct KeyTests {
    @Test func octaveUpDoublesPitch() { #expect(abs(Key.ratio(12) - 2.0) < 1e-6) }
    @Test func octaveDownHalvesPitch() { #expect(abs(Key.ratio(-12) - 0.5) < 1e-6) }
    @Test func zeroIsUnchanged() { #expect(Key.ratio(0) == 1.0) }
    @Test func semitoneUp() { #expect(abs(Key.ratio(1) - 1.059463) < 1e-5) }
    @Test func octaveIs1200Cents() { #expect(Key.cents(12) == 1200) }

    @Test func clampsToSixSemitones() {
        #expect(Key.clamp(9) == 6)
        #expect(Key.clamp(-7) == -6)
        #expect(Key.clamp(3) == 3)
    }

    @Test func labels() {
        #expect(Key.label(2) == "Key +2")
        #expect(Key.label(-3) == "Key −3")
        #expect(Key.label(0) == "Original key")
    }
}
