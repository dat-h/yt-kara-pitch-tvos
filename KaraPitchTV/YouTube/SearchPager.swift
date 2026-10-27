import Foundation

/// Hands out one search's results `pageSize` at a time for the TV, fetching YouTube pages as it
/// goes. A YouTube page has about 20 videos, fewer once live streams and long videos are dropped,
/// so a batch can take more than one page; any extras wait for the next batch.
@MainActor
final class SearchPager {
    typealias Page = (results: [SearchResult], next: String?)

    static let pageSize = 15
    /// Gives up on a batch after this many pages, in case YouTube keeps sending nothing usable.
    static let maxFetchesPerBatch = 4

    private let fetch: @Sendable (_ token: String?) async throws -> Page
    private var token: String?
    private var started = false
    private var seen = Set<String>()
    private var buffer: [SearchResult] = []
    private(set) var isLoading = false

    /// `fetch` gets nil for the first page, then each page's continuation token.
    init(fetch: @escaping @Sendable (_ token: String?) async throws -> Page) {
        self.fetch = fetch
    }

    var hasMore: Bool { !started || token != nil || !buffer.isEmpty }

    /// The next batch, or nothing when the results have run out or a batch is already loading.
    func next() async throws -> [SearchResult] {
        guard !isLoading, hasMore else { return [] }
        isLoading = true
        defer { isLoading = false }
        var fetches = 0
        while buffer.count < Self.pageSize, !started || token != nil, fetches < Self.maxFetchesPerBatch {
            let page = try await fetch(token)
            started = true
            token = page.next
            fetches += 1
            buffer += page.results.filter { seen.insert($0.url).inserted }
        }
        let batch = Array(buffer.prefix(Self.pageSize))
        buffer.removeFirst(batch.count)
        return batch
    }
}
