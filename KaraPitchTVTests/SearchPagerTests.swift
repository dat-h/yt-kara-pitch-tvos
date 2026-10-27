import Testing
@testable import KaraPitchTV

@MainActor
struct SearchPagerTests {
    nonisolated private static func songs(_ range: ClosedRange<Int>) -> [SearchResult] {
        range.map { SearchResult(url: "https://www.youtube.com/watch?v=\($0)", title: "Song \($0)") }
    }

    /// YouTube pages of `perPage` songs, `pages` of them, with a continuation token between.
    private static func pager(perPage: Int, pages: Int) -> SearchPager {
        SearchPager { token in
            let page = Int(token ?? "0")!
            let first = page * perPage + 1
            return (songs(first...(first + perPage - 1)), page + 1 < pages ? String(page + 1) : nil)
        }
    }

    @Test func handsOutFifteenAtATime() async throws {
        let pager = Self.pager(perPage: 12, pages: 4)  // 48 songs, pages smaller than a batch
        #expect(try await pager.next().map(\.title) == (1...15).map { "Song \($0)" })
        #expect(try await pager.next().map(\.title) == (16...30).map { "Song \($0)" })
        #expect(try await pager.next().count == 15)
        #expect(try await pager.next().map(\.title) == ["Song 46", "Song 47", "Song 48"])
        #expect(!pager.hasMore)
        #expect(try await pager.next().isEmpty)
    }

    @Test func dropsSongsSeenOnEarlierPages() async throws {
        let pager = SearchPager { token in
            token == nil ? (Self.songs(1...10), "2") : (Self.songs(6...20), nil)
        }
        let all = try await pager.next() + pager.next()
        #expect(all.count == 20)
        #expect(Set(all.map(\.url)).count == 20)
    }

    @Test func stopsWhenYouTubeKeepsSendingNothing() async throws {
        let pager = SearchPager { _ in ([], "again") }
        #expect(try await pager.next().isEmpty)
    }
}
