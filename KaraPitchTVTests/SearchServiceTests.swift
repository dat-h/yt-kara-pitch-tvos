import Foundation
import SmartTubeIOSCore
import Testing
@testable import KaraPitchTV

/// Ported from the Android app's `SearchServiceTest.kt`.
struct SearchServiceTests {
    @Test func appendsKaraoke() { #expect(SearchService.buildQuery("  bohemian   rhapsody ", addKaraoke: true) == "bohemian rhapsody karaoke") }
    @Test func noDuplicateKaraoke() { #expect(SearchService.buildQuery("abba Karaoke version", addKaraoke: true) == "abba Karaoke version") }
    @Test func exactWhenOff() { #expect(SearchService.buildQuery("abba", addKaraoke: false) == "abba") }

    @Test func addsTheGenreTerm() {
        let country = Genre.all.first { $0.name == "Country" }
        #expect(SearchService.withGenre("  jolene ", country) == "jolene country")
        #expect(SearchService.withGenre("", country) == "country")
        #expect(SearchService.withGenre("Country roads", country) == "Country roads")
        #expect(SearchService.withGenre("jolene", nil) == "jolene")
        #expect(SearchService.withGenre(" ", nil) == "")
    }

    @Test func genreNamesAreUnique() { #expect(Set(Genre.all.map(\.id)).count == Genre.all.count) }

    @Test func keepsSongLengthVideos() {
        #expect(SearchService.keep(durationSec: 240, isLive: false))
        #expect(SearchService.keep(durationSec: 15 * 60, isLive: false))
    }

    @Test func dropsLiveLongAndUnknown() {
        #expect(!SearchService.keep(durationSec: 240, isLive: true))
        #expect(!SearchService.keep(durationSec: 15 * 60 + 1, isLive: false))
        #expect(!SearchService.keep(durationSec: 0, isLive: false))
        #expect(!SearchService.keep(durationSec: -1, isLive: false))
    }

    @Test func resultsAreFilteredDedupedAndCapped() {
        func video(_ id: String, _ duration: TimeInterval?, live: Bool = false) -> Video {
            Video(id: id, title: "T \(id)", channelTitle: "C", duration: duration, isLive: live)
        }
        let videos = [video("aaaaaaaaaaa", 200), video("aaaaaaaaaaa", 200), video("bbbbbbbbbbb", nil), video("ccccccccccc", 200, live: true), video("ddddddddddd", 2000)]
            + (0..<30).map { video(String(format: "x%010d", $0), 100) }
        let results = SearchService.results(from: videos)
        #expect(results.count == SearchService.maxResults)
        #expect(results.first?.url == "https://www.youtube.com/watch?v=aaaaaaaaaaa")
        #expect(results.first?.channel == "C")
        #expect(results.first?.durationSec == 200)
        #expect(Set(results.map(\.url)).count == results.count)
    }
}
