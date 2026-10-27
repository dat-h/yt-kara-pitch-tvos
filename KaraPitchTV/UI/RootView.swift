import SwiftUI

struct RootView: View {
    let session: KaraSession

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            switch session.phase {
            case .idle:
                IdleView(session: session)
            case let .upNext(entry, secondsLeft):
                UpNextCard(entry: entry, secondsLeft: secondsLeft, onStartNow: session.startNow)
            case let .playing(entry):
                PlayerScreen(session: session, entry: entry)
            }
            FloatersOverlay(floaters: session.floaters)
            if let notice = session.notice {
                // Below the ticker.
                NoticeView(text: notice).padding(.top, 176).transition(.opacity)
            }
            AddedBannerLayer(session: session)
        }
        .animation(.easeInOut(duration: 0.2), value: session.notice)
        .fullScreenCover(isPresented: Bindable(session).searchOpen) { SearchView(session: session) }
    }
}

private struct PlayerScreen: View {
    let session: KaraSession
    let entry: QueueEntry
    @State private var controlsOpen = false

    var body: some View {
        let snapshot = session.player.snapshot
        ZStack {
            PlayerHost(
                player: session.player, backdrop: session.backdrop.player, backgroundOn: session.backgroundVideoOn && session.backdrop.isReady,
                takesFocus: !controlsOpen, onAction: handle
            )
            .ignoresSafeArea()
            if snapshot.durationMs == 0 { LoadingCard(entry: entry).ignoresSafeArea() }
            if snapshot.paused && snapshot.durationMs > 0 { NoticeView(text: "Paused") }
            Ticker(state: session.queue).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea(edges: .top)
            if controlsOpen {
                ControlOverlay(session: session) { controlsOpen = false }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controlsOpen)
        // Back must never leave the app mid-song. The player view normally takes it; this catches
        // it if focus is elsewhere for a moment (the overlay handles its own Back).
        .onExitCommand {
            if !controlsOpen { session.backPressed() }
        }
    }

    private func handle(_ action: RemoteAction) {
        switch action {
        case .keyUp: session.adjustKey(+1)
        case .keyDown: session.adjustKey(-1)
        case .seekBack: session.player.seek(by: -10)
        case .seekForward: session.player.seek(by: +10)
        case .skip: session.skip(notice: "Skipped")
        case .togglePause: session.player.togglePause()
        case .back: session.backPressed()
        case .openControls: controlsOpen = true
        }
    }
}
