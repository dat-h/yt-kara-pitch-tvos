import Testing
@testable import KaraPitchTV

struct MusicVideoMatcherTests {
    @Test(arguments: [
        ("ABBA - Dancing Queen (Karaoke Version)", "ABBA Dancing Queen"),
        ("Dancing Queen - ABBA | Karaoke Version | KaraFun", "Dancing Queen ABBA"),
        ("Dancing Queen - ABBA (Karaoke Songs With Lyrics - Original Key)", "Dancing Queen ABBA"),
        ("ABBA - Dancing Queen (Karaoke Piano)", "ABBA Dancing Queen"),
        ("R.E.M. • Fireplace | Karaoke • Instrumental • Lyrics", "R E M Fireplace"),
        ("Dancing Queen (Originally Performed by ABBA) [Karaoke Version]", "Dancing Queen ABBA"),
        ("Beyoncé - Halo (Lower Key) Karaoke HD", "Beyoncé Halo"),
    ])
    func cleansKaraokeTitles(title: String, query: String) {
        #expect(MusicVideoMatcher.songQuery(fromKaraokeTitle: title) == query)
    }

    @Test func splitsTheArtistFromTheSong() {
        #expect(MusicVideoMatcher.songParts(fromKaraokeTitle: "Dancing Queen - ABBA | Karaoke Version | KaraFun") == ["Dancing Queen", "ABBA"])
        #expect(MusicVideoMatcher.songParts(fromKaraokeTitle: "Dancing Queen (Originally Performed by ABBA) [Karaoke]") == ["Dancing Queen", "ABBA"])
        #expect(MusicVideoMatcher.songParts(fromKaraokeTitle: "Twenty-One Pilots - Stressed Out (Karaoke)") == ["Twenty One Pilots", "Stressed Out"])
    }

    @Test func searchesForTheOfficialVideo() {
        #expect(MusicVideoMatcher.searchQuery(fromKaraokeTitle: "ABBA - Dancing Queen (Karaoke Version)") == "ABBA Dancing Queen official music video")
    }

    private let karaoke = "ABBA - Dancing Queen (Karaoke Version)"

    private func rank(_ candidates: [MusicVideoCandidate], duration: Int64 = 240) -> [String] {
        MusicVideoMatcher.rank(candidates, karaokeTitle: karaoke, karaokeID: "karaoke1", karaokeDurationSec: duration).map(\.id)
    }

    @Test func prefersTheOfficialVideoOverEverythingElse() {
        let candidates = [
            MusicVideoCandidate(id: "lyric", title: "ABBA - Dancing Queen (Lyrics)", channel: "Lyric Hub", durationSec: 232),
            MusicVideoCandidate(id: "live", title: "ABBA - Dancing Queen (Live in Stockholm)", channel: "ABBA", durationSec: 245),
            MusicVideoCandidate(id: "cover", title: "Dancing Queen - ABBA cover", channel: "Some Band", durationSec: 230),
            MusicVideoCandidate(id: "topic", title: "Dancing Queen", channel: "ABBA - Topic", durationSec: 231),
            MusicVideoCandidate(id: "long", title: "ABBA - Dancing Queen (Official Music Video) 1 hour loop", channel: "Loops", durationSec: 3600),
            MusicVideoCandidate(id: "official", title: "Abba - Dancing Queen (Official Music Video Remastered)", channel: "ABBA", durationSec: 232),
            MusicVideoCandidate(id: "karaoke1", title: "ABBA - Dancing Queen (Karaoke Version)", channel: "Sing King", durationSec: 240),
        ]
        #expect(rank(candidates) == ["official"])
    }

    @Test func ranksVevoAboveAFanUpload() {
        let candidates = [
            MusicVideoCandidate(id: "fan", title: "ABBA Dancing Queen music video HQ", channel: "70s Hits Archive", durationSec: 235),
            MusicVideoCandidate(id: "vevo", title: "ABBA - Dancing Queen (Official Video)", channel: "ABBAVEVO", durationSec: 232),
        ]
        #expect(rank(candidates) == ["vevo", "fan"])
    }

    @Test func rejectsOtherSongs() {
        let candidates = [
            MusicVideoCandidate(id: "other", title: "ABBA - Mamma Mia (Official Music Video)", channel: "ABBA", durationSec: 215),
            MusicVideoCandidate(id: "unrelated", title: "Queen - Bohemian Rhapsody (Official Video)", channel: "Queen Official", durationSec: 359),
        ]
        #expect(rank(candidates).isEmpty)
    }

    @Test func rejectsTheArtistsOtherSongsAndOtherArtistsVersions() {
        let other = [
            MusicVideoCandidate(id: "otherSong", title: "R.E.M. - Imitation Of Life (Official Music Video)", channel: "remhq", durationSec: 238),
            MusicVideoCandidate(id: "right", title: "R.E.M. - Fireplace", channel: "Antonio Falcone", durationSec: 204),
        ]
        let ranked = MusicVideoMatcher.rank(other, karaokeTitle: "R.E.M. • Fireplace | Karaoke • Instrumental • Lyrics", karaokeID: "k", karaokeDurationSec: 210)
        #expect(ranked.map(\.id) == ["right"])

        let otherArtist = [MusicVideoCandidate(id: "ateens", title: "A*Teens - Dancing Queen", channel: "A*Teens Official", durationSec: 267)]
        #expect(rank(otherArtist).isEmpty)
    }

    @Test func keepsWordsTheKaraokeTitleHasToo() {
        let candidates = [MusicVideoCandidate(id: "remix", title: "Dancing Queen (Remix) - ABBA Official Video", channel: "ABBA", durationSec: 250)]
        let ranked = MusicVideoMatcher.rank(candidates, karaokeTitle: "ABBA - Dancing Queen Remix (Karaoke)", karaokeID: "k", karaokeDurationSec: 250)
        #expect(ranked.map(\.id) == ["remix"])
    }

    @Test func triesAtMostThree() {
        let candidates = (0..<6).map { MusicVideoCandidate(id: "v\($0)", title: "ABBA Dancing Queen video \($0)", channel: "c", durationSec: 240) }
        #expect(rank(candidates) == ["v0", "v1", "v2"])
    }
}
