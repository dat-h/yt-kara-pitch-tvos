import SwiftUI

/// The strip across the top of the video and the search screen: the song playing now, then the
/// next three that haven't failed, with the phone QR code at the right end. Always
/// shown, so phones can join at any time.
struct Ticker: View {
    static let velocity: Double = 100  // points per second
    static let gap = "      ♪      "
    static let emptyText = "Nothing queued yet. Scan the code to add songs from your phone."

    let state: QueueState

    var body: some View {
        let runs = Self.runs(nowPlaying: state.nowPlaying, upcoming: state.queue.filter { $0.status != .error })
        HStack(spacing: 32) {
            Text("QUEUE").font(.system(size: 28, weight: .bold)).kerning(4).foregroundStyle(Theme.pink)
            Marquee(text: runs.isEmpty ? AttributedString(Self.emptyText) : Self.styled(runs))
            PhoneQRBadge()
        }
        .padding(.leading, 64)
        .padding(.trailing, 24)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.opacity(0.78))
    }

    /// What each piece of the ticker is, which sets its color.
    enum Part {
        case rank, singer, title, detail
    }

    typealias Run = (text: String, part: Part)

    /// `Now: Singer — Title`, then `1. Singer — Title (Key +2)`, with a note between songs.
    static func runs(nowPlaying: QueueEntry?, upcoming: [QueueEntry]) -> [Run] {
        let now = nowPlaying.map { [Run("Now: ", .rank)] + line($0) }
        let next = upcoming.prefix(3).enumerated().map { index, entry in [Run("\(index + 1). ", .rank)] + line(entry) }
        let songs = [now].compactMap { $0 } + next
        return songs.enumerated().flatMap { index, song in index == 0 ? song : [Run(gap, .detail)] + song }
    }

    static func text(nowPlaying: QueueEntry?, upcoming: [QueueEntry]) -> String {
        runs(nowPlaying: nowPlaying, upcoming: upcoming).map(\.text).joined()
    }

    static func color(_ part: Part) -> Color {
        switch part {
        case .rank: Theme.orange
        case .singer: Theme.pink
        case .title: Theme.text
        case .detail: Theme.textDim
        }
    }

    static func styled(_ runs: [Run]) -> AttributedString {
        runs.reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            piece.foregroundColor = color(run.part)
            if run.part != .detail && run.part != .title { piece.font = .system(size: 36, weight: .bold) }
            result += piece
        }
    }

    private static func line(_ entry: QueueEntry) -> [Run] {
        var runs: [Run] = []
        if !entry.singer.isEmpty { runs += [(entry.singer, .singer), (" — ", .detail)] }
        runs.append((entry.title, .title))
        if entry.presetKey != 0 { runs.append((" (\(Key.label(entry.presetKey)))", .detail)) }
        return runs
    }
}

/// One line of text scrolling left forever, drawn twice so the loop has no seam.
private struct Marquee: View {
    let text: AttributedString
    @State private var width: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = width + 240
            let offset = cycle > 240 ? -(context.date.timeIntervalSinceReferenceDate * Ticker.velocity).truncatingRemainder(dividingBy: cycle) : 0
            HStack(spacing: 240) {
                label
                label
            }
            .offset(x: offset)
        }
        // minWidth 0: without it the frame takes on the text's full width, which pushes the whole ticker,
        // and anything sized with it, off both sides of the screen.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 36))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}
