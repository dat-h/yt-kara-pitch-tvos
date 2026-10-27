import SwiftUI

@main
struct KaraPitchTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = KaraSession()
    @State private var server: HTTPServer?

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .task {
                    session.start()
                    let server = HTTPServer(router: session.makeRouter())
                    server.start()
                    self.server = server
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keeps the screensaver away on every screen, idle included.
            UIApplication.shared.isIdleTimerDisabled = phase == .active
            session.setActive(phase == .active)
            // The listener can die while the app is suspended; bring it back.
            if phase == .active { server?.start() }
        }
    }
}
