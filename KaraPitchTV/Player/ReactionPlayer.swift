import AVFoundation
import os

/// An audience reaction a phone can send, played over the song.
enum Reaction: String, CaseIterable, Sendable {
    case clap, ovation, boo, laugh
}

/// Plays reaction sounds from `Resources/sounds` (real recordings, see `CREDITS.md` there) on top
/// of whatever is playing. They don't go through the pitch tap, so the key never changes them. A
/// few copies of each are loaded so quick presses from several phones overlap instead of cutting
/// each other off.
@MainActor
final class ReactionPlayer {
    static let copies = 3
    static let volume: Float = 0.8

    private var players: [Reaction: [AVAudioPlayer]] = [:]

    init() {
        for reaction in Reaction.allCases {
            guard let url = Bundle.main.url(forResource: reaction.rawValue, withExtension: "m4a", subdirectory: "sounds")
                ?? Bundle.main.url(forResource: reaction.rawValue, withExtension: "m4a")
            else {
                Logger.player.error("missing sound \(reaction.rawValue, privacy: .public).m4a")
                continue
            }
            players[reaction] = (0..<Self.copies).compactMap { _ in
                let player = try? AVAudioPlayer(contentsOf: url)
                player?.volume = Self.volume
                player?.prepareToPlay()
                return player
            }
        }
    }

    /// Plays on an idle copy. When all copies are busy the press is dropped, which keeps a burst
    /// of presses from piling up into noise.
    func play(_ reaction: Reaction) {
        guard let player = players[reaction]?.first(where: { !$0.isPlaying }) else { return }
        player.currentTime = 0
        player.play()
    }
}
