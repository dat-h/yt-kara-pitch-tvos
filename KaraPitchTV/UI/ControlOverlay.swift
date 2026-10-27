import SwiftUI

/// Opened with a swipe down during a song: Search, Skip, Restart and a key stepper. Closes on Back,
/// or by itself after `idleTimeout` without input.
struct ControlOverlay: View {
    static let idleTimeout: Duration = .seconds(8)

    let session: KaraSession
    let onClose: () -> Void

    private enum Control: Hashable { case search, skip, restart, keyDown, keyUp }
    @FocusState private var focused: Control?
    /// Bumped on every input; the close timer restarts whenever it changes.
    @State private var lastInput = 0

    var body: some View {
        HStack(spacing: 48) {
            Button("Search", systemImage: "magnifyingglass") { act { session.searchOpen = true } }
                .focused($focused, equals: .search)
            Button("Skip", systemImage: "forward.end.fill") { act { session.skip(notice: "Skipped") } }
                .focused($focused, equals: .skip)
            Button("Restart song", systemImage: "backward.end.fill") {
                act {
                    session.player.restart()
                    session.notify("Restarted")
                }
            }
            .focused($focused, equals: .restart)
            Spacer().frame(width: 40)
            Button("Key down", systemImage: "minus") { touch { session.adjustKey(-1) } }
                .labelStyle(.iconOnly)
                .focused($focused, equals: .keyDown)
            Text(Key.label(session.player.key))
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(minWidth: 300)
            Button("Key up", systemImage: "plus") { touch { session.adjustKey(+1) } }
                .labelStyle(.iconOnly)
                .focused($focused, equals: .keyUp)
        }
        .padding(48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 40))
        .padding(.bottom, 64)
        .defaultFocus($focused, .keyUp)
        .onExitCommand(perform: onClose)
        .onChange(of: focused) { lastInput += 1 }
        .task(id: lastInput) {
            do {
                try await Task.sleep(for: Self.idleTimeout)
                onClose()
            } catch {}
        }
    }

    /// An action that ends the overlay's job.
    private func act(_ action: () -> Void) {
        action()
        onClose()
    }

    /// An action that keeps the overlay open.
    private func touch(_ action: () -> Void) {
        action()
        lastInput += 1
    }
}
