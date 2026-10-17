import SwiftUI

/// Shown while nothing is ready to play: the heading, Search (focused), the phone URL with its QR
/// code, and the next songs in the queue.
struct IdleView: View {
    static let addressRefresh: Duration = .seconds(15)

    let session: KaraSession
    @State private var phoneURL = LocalAddress.phoneURL()
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 80) {
            details
            if let phoneURL, let qr = QRCode.image(for: phoneURL) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 520, height: 520)
                    .padding(28)
                    .background(.white, in: RoundedRectangle(cornerRadius: 32))
                    .accessibilityLabel("QR code for \(phoneURL)")
            }
        }
        .padding(.horizontal, 112)
        .padding(.vertical, 80)
        .defaultFocus($searchFocused, true)
        .task {
            while !Task.isCancelled {
                phoneURL = LocalAddress.phoneURL()
                try? await Task.sleep(for: Self.addressRefresh)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Karaoke").font(.system(size: 104, weight: .black)).foregroundStyle(Theme.text)
            Capsule().fill(Theme.accent).frame(width: 240, height: 12).padding(.top, 12)
            Text("Search on the TV, or add from your phone").font(.system(size: 48, weight: .semibold)).foregroundStyle(Theme.text)
                .padding(.top, 56)
            Button("Search songs", systemImage: "magnifyingglass") { session.searchOpen = true }
                .focused($searchFocused)
                .padding(.top, 28)
            Text("On your phone: scan the code, or open").font(.system(size: 36)).foregroundStyle(Theme.textDim).padding(.top, 28)
            Text(phoneURL ?? "No network").font(.system(size: 52, weight: .bold)).foregroundStyle(Theme.orange)
            UpNextList(queue: session.queue.queue).padding(.top, 56)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct UpNextList: View {
    let queue: [QueueEntry]

    var body: some View {
        if !queue.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("UP NEXT").font(.system(size: 28, weight: .bold)).kerning(4).foregroundStyle(Theme.textDim)
                ForEach(Array(queue.prefix(5).enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 20) {
                        Text("\(index + 1)").font(.system(size: 36, weight: .bold)).foregroundStyle(Theme.pink).frame(width: 56, alignment: .leading)
                        Text(line(entry)).font(.system(size: 36)).lineLimit(1)
                            .foregroundStyle(entry.status == .error ? Theme.textDim : Theme.text)
                        if entry.presetKey != 0 { KeyChip(key: entry.presetKey) }
                    }
                }
                if queue.count > 5 {
                    Text("+ \(queue.count - 5) more").font(.system(size: 32)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private func line(_ entry: QueueEntry) -> String {
        (entry.singer.isEmpty ? "" : "\(entry.singer) · ") + (entry.status == .resolving ? "Getting ready…" : entry.title)
    }
}
