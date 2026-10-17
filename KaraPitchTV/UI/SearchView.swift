import SwiftUI

/// Full-screen search on the TV, drawn over whatever is playing (the song keeps going). Back closes
/// the add sheet first, then the screen. Songs added here are ready at once, and search stays open.
/// A genre tile narrows the search to that genre, or browses it when nothing is typed.
struct SearchView: View {
    let session: KaraSession

    private enum Results {
        case empty, loading
        case loaded([SearchResult])
        case failed(String)
    }

    private enum Focus: Hashable {
        case field
        case genre(String)
        case result(String)
    }

    @State private var query = ""
    @State private var karaoke = true
    @State private var genre: Genre?
    @State private var results = Results.empty
    @State private var picked: SearchResult?
    @State private var searchTask: Task<Void, Never>?
    @State private var pager: SearchPager?
    /// The next batch is loading, after reaching the bottom of the results.
    @State private var loadingMore = false
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 0) {
            Ticker(state: session.queue).ignoresSafeArea(edges: .top)
            search
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        // Search covers the root view, so it shows the "added to queue" banner itself.
        .overlay { AddedBannerLayer(session: session) }
        .defaultFocus($focus, .field)
        .sheet(item: $picked) { result in
            QuickAddSheet(result: result, singers: session.recentSingers(), onNewName: session.rememberSinger) { singer, key in
                Task {
                    await session.addFromSearch(result, singer: singer, key: key)
                    picked = nil
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    static let columns = 5
    /// Room around the result grid inside its scroll view, so a focused card can grow without being
    /// cut off, while the scroll view still clips anything scrolled up above it.
    static let gridInset: CGFloat = 40

    private var search: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search songs").font(.system(size: 44, weight: .black)).foregroundStyle(Theme.text)
                Spacer()
                Text("Back to close").font(.system(size: 26)).foregroundStyle(Theme.textDim)
            }
            HStack(spacing: 32) {
                TextField("Song or artist", text: $query)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                    .focused($focus, equals: .field)
                Button(karaoke ? "+ karaoke ✓" : "+ karaoke") {
                    karaoke.toggle()
                    if case .loaded = results { runSearch() }
                }
                Button("Search", action: runSearch)
            }
            genres
            content
        }
        .padding(.horizontal, 80)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// One row of genre tiles. Select picks a genre and searches; Select on the picked one clears it.
    private var genres: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 32) {
                ForEach(Genre.all) { item in
                    Button {
                        genre = genre == item ? nil : item
                        runSearch()
                    } label: {
                        GenreTile(genre: item, selected: genre == item)
                    }
                    .buttonStyle(.card)
                    .focused($focus, equals: .genre(item.id))
                }
            }
            .padding(.vertical, 16)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch results {
        case .empty:
            hint("Type a song or artist, or pick a genre.")
        case .loading:
            HStack(spacing: 24) {
                ProgressView()
                hint("Searching…")
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 24) {
                hint(message)
                Button("Retry", action: runSearch)
            }
        case let .loaded(items) where items.isEmpty:
            hint("No songs found. Try different words.")
        case let .loaded(items):
            // Clipped, unlike the genre row: cards scrolled up must not draw over the tiles.
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 36), count: Self.columns), spacing: 48) {
                    ForEach(Array(items.enumerated()), id: \.element.url) { index, result in
                        Button { picked = result } label: { ResultCard(result: result) }
                            .buttonStyle(.card)
                            .focused($focus, equals: .result(result.url))
                            // The last row coming into view loads the next batch.
                            .onAppear { if index >= items.count - Self.columns { loadMore() } }
                    }
                }
                .padding(Self.gridInset)
                if loadingMore {
                    HStack(spacing: 24) {
                        ProgressView()
                        hint("Loading more…")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Self.gridInset)
                }
            }
            .padding(.horizontal, -Self.gridInset)
            .clipped()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 36)).foregroundStyle(Theme.textDim)
    }

    private func runSearch() {
        let q = SearchService.withGenre(query, genre)
        guard !q.isEmpty else {
            // The last genre was cleared with nothing typed: back to the start.
            searchTask?.cancel()
            results = .empty
            return
        }
        searchTask?.cancel()
        results = .loading
        loadingMore = false
        let pager = session.searchPager(q, addKaraoke: karaoke)
        self.pager = pager
        searchTask = Task {
            do {
                let items = try await pager.next()
                guard !Task.isCancelled else { return }
                results = .loaded(items)
                if let first = items.first { focus = .result(first.url) }
            } catch {
                guard !Task.isCancelled else { return }
                results = .failed("Search didn't work. Check the connection and try again.")
            }
        }
    }

    /// Adds the next batch to the results. A failure here keeps what's shown; reaching the bottom
    /// again retries.
    private func loadMore() {
        guard let pager, case .loaded = results, pager.hasMore, !pager.isLoading else { return }
        loadingMore = true
        searchTask = Task {
            defer { if self.pager === pager { loadingMore = false } }
            guard let more = try? await pager.next(), !Task.isCancelled, self.pager === pager,
                case let .loaded(items) = results
            else { return }
            results = .loaded(items + more)
        }
    }
}

private struct GenreTile: View {
    let genre: Genre
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(genre.emoji).font(.system(size: 44))
            Text(genre.name).font(.system(size: 32, weight: .bold)).foregroundStyle(.white).lineLimit(1).fixedSize()
            if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(.white) }
        }
        .padding(.horizontal, 28)
        .frame(height: 96)
        .background(
            LinearGradient(
                colors: [Color(hue: genre.hue, saturation: 0.7, brightness: 0.75), Color(hue: genre.hue, saturation: 0.8, brightness: 0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(.white, lineWidth: 5) } }
    }
}

extension SearchResult: Identifiable {
    var id: String { url }
}

private struct ResultCard: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: result.thumb.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.surfaceHigh
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if result.durationSec > 0 {
                    Text(String(format: "%d:%02d", result.durationSec / 60, result.durationSec % 60))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(result.title).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                if let channel = result.channel {
                    Text(channel).font(.system(size: 20)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.surface)
    }
}
