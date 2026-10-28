import Testing
@testable import KaraPitchTV

/// When the music video plays behind the song.
@MainActor
struct BackdropRuleTests {
    private let playing = Phase.playing(QueueEntry(id: "1", url: "u", title: "Song"))

    @Test func playsOnlyWhileTheSongMoves() {
        #expect(KaraSession.backdropPlays(phase: playing, backgroundOn: true, active: true, songMoving: true))
        // Paused: the music video waits with it.
        #expect(!KaraSession.backdropPlays(phase: playing, backgroundOn: true, active: true, songMoving: false))
    }

    @Test func staysStillWhenOffAwayOrBetweenSongs() {
        #expect(!KaraSession.backdropPlays(phase: playing, backgroundOn: false, active: true, songMoving: true))
        #expect(!KaraSession.backdropPlays(phase: playing, backgroundOn: true, active: false, songMoving: true))
        #expect(!KaraSession.backdropPlays(phase: .idle, backgroundOn: true, active: true, songMoving: true))
    }
}
