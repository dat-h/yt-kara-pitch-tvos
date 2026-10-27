import SwiftUI

/// The session's current "added to queue" banner, sliding in at the bottom of whichever screen
/// shows it: the root view, and the search screen that covers it.
struct AddedBannerLayer: View {
    let session: KaraSession

    var body: some View {
        ZStack {
            if let banner = session.banner {
                AddedBanner(entry: banner, position: (session.queue.queue.firstIndex { $0.id == banner.id } ?? -1) + 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.35), value: session.banner)
    }
}

/// Slides up from the bottom for a few seconds whenever a song becomes ready to play.
struct AddedBanner: View {
    let entry: QueueEntry
    /// 1-based position in the queue, or 0 when it's no longer there.
    let position: Int

    var body: some View {
        HStack(spacing: 32) {
            AsyncImage(url: entry.thumb.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.surfaceHigh
            }
            .frame(width: 256, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 8) {
                Text(position > 0 ? "ADDED TO QUEUE · #\(position)" : "ADDED TO QUEUE")
                    .font(.system(size: 26, weight: .bold)).kerning(4).foregroundStyle(Theme.pink)
                Text(entry.title).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 20) {
                    Text(entry.singer.isEmpty ? "No name" : entry.singer).font(.system(size: 32)).foregroundStyle(Theme.textDim).lineLimit(1)
                    if entry.presetKey != 0 { KeyChip(key: entry.presetKey) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 1240)
        .background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 36))
        .padding(.bottom, 64)
    }
}
