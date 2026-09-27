import AVFoundation
import AVKit
import SwiftUI

/// The looping, muted Settings walkthrough on "Turn on the keyboard". Tapping "Open Settings" starts
/// Picture in Picture so the video floats over Settings. `nil` when the recording isn't in the bundle.
///
/// Drop the recordings into App/Resources/: `guide-keyboard.mp4` (iPhone) and `guide-keyboard-ipad.mp4`.
@MainActor
final class GuidePlayer: NSObject, AVPictureInPictureControllerDelegate {
    let view = PlayerView()
    private let player = AVQueuePlayer()
    private let looper: AVPlayerLooper
    private var pip: AVPictureInPictureController?
    private var ownsSession = false

    static func make() -> GuidePlayer? {
        let name = UIDevice.current.userInterfaceIdiom == .pad ? "guide-keyboard-ipad" : "guide-keyboard"
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4")
            ?? Bundle.main.url(forResource: "guide-keyboard", withExtension: "mp4") else { return nil }
        return GuidePlayer(url: url)
    }

    private init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        super.init()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: view.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            pip?.delegate = self
            self.pip = pip
        }
    }

    func play() {
        // PiP needs a playback-capable session. When the mic is on, DictationController's playAndRecord
        // session already is one; only when it's off do we set a mixable playback session ourselves.
        if !DictationController.micEnabled, KeyboardHandoff.status() == .off {
            let session = AVAudioSession.sharedInstance()
            ownsSession = (try? session.setCategory(.playback, options: [.mixWithOthers])) != nil
            try? session.setActive(true)
        }
        player.play()
    }

    /// Floats the guide over Settings; call just before opening Settings.
    func startPiP() {
        guard let pip, pip.isPictureInPicturePossible, !pip.isPictureInPictureActive else { return }
        pip.startPictureInPicture()
    }

    func stopPiP() {
        guard let pip, pip.isPictureInPictureActive else { return }
        pip.stopPictureInPicture()
    }

    func stop() {
        stopPiP()
        player.pause()
        // Hand the session back untouched if the mic came on meanwhile.
        if ownsSession, !DictationController.micEnabled, KeyboardHandoff.status() == .off {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        ownsSession = false
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

/// A view backed by an `AVPlayerLayer`, so PiP can take the layer that's on screen.
final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct GuideVideo: UIViewRepresentable {
    let guide: GuidePlayer

    func makeUIView(context: Context) -> PlayerView { guide.view }
    func updateUIView(_ view: PlayerView, context: Context) {}
}
