import SwiftUI

/// The 5-second count-in before a song. Select starts it at once.
struct UpNextCard: View {
    let entry: QueueEntry
    let secondsLeft: Int
    let onStartNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("UP NEXT").font(.system(size: 40, weight: .bold)).kerning(8).foregroundStyle(Theme.pink)
            Text(entry.singer.isEmpty ? "Next singer" : entry.singer)
                .font(.system(size: 144, weight: .black)).foregroundStyle(Theme.text).lineLimit(1).padding(.top, 24)
            Text(entry.title).font(.system(size: 52)).foregroundStyle(Theme.textDim).lineLimit(2).multilineTextAlignment(.center)
                .padding(.top, 16)
            KeyChip(key: entry.presetKey, big: true).padding(.top, 40)
            Text("Starting in \(secondsLeft)").font(.system(size: 60, weight: .bold)).foregroundStyle(Theme.orange).padding(.top, 72)
            // The focused button turns Select into "start now"; it's styled as the hint text.
            Button(action: onStartNow) {
                Text("Press Select to start now").font(.system(size: 32)).foregroundStyle(Theme.textDim)
            }
            .buttonStyle(.plain)
        }
        .padding(112)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Covers the screen until the video's first frame.
struct LoadingCard: View {
    let entry: QueueEntry

    var body: some View {
        VStack(spacing: 16) {
            Text(entry.singer.isEmpty ? "Here we go" : entry.singer).font(.system(size: 96, weight: .black)).foregroundStyle(Theme.text)
            Text("Loading “\(entry.title)”…").font(.system(size: 44)).foregroundStyle(Theme.textDim).lineLimit(1)
        }
        .padding(112)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
