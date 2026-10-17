import Foundation

/// A song's key offset in whole semitones.
enum Key {
    static let range = -6...6

    static func clamp(_ semitones: Int) -> Int { min(max(semitones, range.lowerBound), range.upperBound) }

    /// NewTimePitch's pitch parameter for `semitones`: +12 is 1200 cents. Not clamped.
    static func cents(_ semitones: Int) -> Float { Float(semitones * 100) }

    /// Frequency multiplier for `semitones`: +12 is an octave up (2.0). Not clamped.
    static func ratio(_ semitones: Int) -> Float { Float(pow(2.0, Double(semitones) / 12.0)) }

    static func label(_ semitones: Int) -> String {
        if semitones > 0 { "Key +\(semitones)" } else if semitones < 0 { "Key −\(-semitones)" } else { "Original key" }
    }
}
