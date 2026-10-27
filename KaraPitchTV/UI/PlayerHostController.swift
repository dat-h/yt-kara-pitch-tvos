import AVFoundation
import SwiftUI
import UIKit

/// What the Siri Remote asks of the player (SPEC §6.2).
enum RemoteAction: Equatable {
    case keyUp, keyDown, seekBack, seekForward, skip, togglePause, back, openControls
}

/// Full-screen player that reads the Siri Remote as `UIPress` types, so directional *clicks* stay
/// apart from swipes. Holding right for `holdToSkip` skips instead of seeking. With background
/// video on, the karaoke video is drawn keyed over the backdrop instead of in its `AVPlayerLayer`.
final class PlayerHostController: UIViewController {
    static let holdToSkip: Duration = .seconds(1)

    var onAction: (RemoteAction) -> Void = { _ in }
    /// False while the control overlay is open, so its buttons get the focus and the presses.
    var takesFocus = true {
        didSet {
            guard takesFocus != oldValue else { return }
            (view as? PlayerLayerView)?.focusable = takesFocus
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }
    /// The backdrop shows through the karaoke video's background.
    var backgroundOn = false {
        didSet { (viewIfLoaded as? PlayerLayerView)?.backgroundOn = backgroundOn }
    }
    private let player: KaraPlayer
    private let backdrop: AVPlayer
    /// Bumped on each right press, so a hold timer can tell whether it's still the same press.
    private var rightPress = 0
    private var rightHeldToSkip = false

    init(player: KaraPlayer, backdrop: AVPlayer) {
        self.player = player
        self.backdrop = backdrop
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let view = PlayerLayerView(player: player, backdrop: backdrop)
        view.backgroundOn = backgroundOn
        // Swipes on the clickpad, not clicks: the indirect touch type keeps them apart from presses.
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipe.direction = .down
        swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        view.addGestureRecognizer(swipe)
        self.view = view
    }

    @objc private func swipedDown() { onAction(.openControls) }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] { [view] }

    /// The presses this controller owns. None of their phases may reach `super`: a Menu press whose
    /// end goes up the responder chain makes tvOS leave the app.
    private static let handled: Set<UIPress.PressType> = [.upArrow, .downArrow, .leftArrow, .rightArrow, .select, .playPause, .menu]

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .upArrow: onAction(.keyUp)
            case .downArrow: onAction(.keyDown)
            case .leftArrow: onAction(.seekBack)
            case .rightArrow: rightDown()
            case .select, .playPause: onAction(.togglePause)
            case .menu: onAction(.back)
            default: break
            }
        }
        forwardUnhandled(presses) { super.pressesBegan($0, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        forwardUnhandled(presses) { super.pressesChanged($0, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .rightArrow }) { rightUp(seek: true) }
        forwardUnhandled(presses) { super.pressesEnded($0, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .rightArrow }) { rightUp(seek: false) }
        forwardUnhandled(presses) { super.pressesCancelled($0, with: event) }
    }

    private func forwardUnhandled(_ presses: Set<UIPress>, to forward: (Set<UIPress>) -> Void) {
        let unhandled = presses.filter { !Self.handled.contains($0.type) }
        if !unhandled.isEmpty { forward(unhandled) }
    }

    private func rightDown() {
        rightPress += 1
        rightHeldToSkip = false
        let press = rightPress
        Task { [weak self] in
            try? await Task.sleep(for: Self.holdToSkip)
            guard let self, self.rightPress == press else { return }
            self.rightHeldToSkip = true
            self.onAction(.skip)
        }
    }

    private func rightUp(seek: Bool) {
        if seek && !rightHeldToSkip { onAction(.seekForward) }
        rightPress += 1  // cancels the hold timer
    }
}

/// The backdrop at the bottom, then the karaoke video either plain or keyed.
private final class PlayerLayerView: UIView {
    private let backdropLayer = AVPlayerLayer()
    private let playerLayer = AVPlayerLayer()
    private let keyedView: KeyedVideoView
    var focusable = true
    override var canBecomeFocused: Bool { focusable }

    var backgroundOn = false {
        didSet {
            backdropLayer.isHidden = !backgroundOn
            playerLayer.isHidden = backgroundOn
            keyedView.isHidden = !backgroundOn
            keyedView.isShown = backgroundOn
        }
    }

    init(player: KaraPlayer, backdrop: AVPlayer) {
        keyedView = KeyedVideoView(player: player)
        super.init(frame: .zero)
        backgroundColor = .black
        backdropLayer.player = backdrop
        backdropLayer.videoGravity = .resizeAspectFill
        backdropLayer.isHidden = true
        playerLayer.player = player.player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(backdropLayer)
        layer.addSublayer(playerLayer)
        keyedView.isHidden = true
        addSubview(keyedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.frame = bounds
        playerLayer.frame = bounds
        CATransaction.commit()
        keyedView.frame = bounds
    }
}

struct PlayerHost: UIViewControllerRepresentable {
    let player: KaraPlayer
    let backdrop: AVPlayer
    var backgroundOn = false
    var takesFocus = true
    let onAction: (RemoteAction) -> Void

    func makeUIViewController(context: Context) -> PlayerHostController {
        let controller = PlayerHostController(player: player, backdrop: backdrop)
        controller.onAction = onAction
        controller.backgroundOn = backgroundOn
        return controller
    }

    func updateUIViewController(_ controller: PlayerHostController, context: Context) {
        controller.onAction = onAction
        controller.takesFocus = takesFocus
        controller.backgroundOn = backgroundOn
    }
}
