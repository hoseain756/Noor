import Flutter
import UIKit

/// Forwards ACTION-VIEW-style links (custom-scheme OAuth returns, magnet
/// links, App/Universal Links) to the Dart side over the `noor/links`
/// EventChannel — the same channel the Android host uses, so Dart routing
/// stays platform-agnostic.
///
/// Links captured before Dart starts listening (cold start) are parked and
/// delivered on first listen, mirroring Android's pendingLink behavior.
final class NoorLinkForwarder: NSObject, FlutterStreamHandler {
    static let shared = NoorLinkForwarder()

    private var sink: FlutterEventSink?
    private var pending: String?
    private var attached = false

    /// Registers the `noor/links` EventChannel on the engine's messenger.
    /// Idempotent: safe to call on every scene connection / URL event.
    func attach(messenger: FlutterBinaryMessenger) {
        guard !attached else { return }
        attached = true
        FlutterEventChannel(name: "noor/links", binaryMessenger: messenger)
            .setStreamHandler(self)
    }

    func forward(_ link: String) {
        if let sink = sink {
            DispatchQueue.main.async { sink(link) }
        } else {
            pending = link
        }
    }

    func onListen(
        withArguments _: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        if let pending {
            self.pending = nil
            DispatchQueue.main.async { events(pending) }
        }
        return nil
    }

    func onCancel(withArguments _: Any?) {
        sink = nil
    }
}

class SceneDelegate: FlutterSceneDelegate {

    // MARK: - Scene lifecycle

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        attachForwarder()
        // Cold-start deep link (app launched by tapping a noor:// or
        // app.noor.mobile:// URL).
        for context in connectionOptions.urlContexts {
            NoorLinkForwarder.shared.forward(context.url.absoluteString)
        }
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        super.scene(scene, openURLContexts: URLContexts)
        attachForwarder()
        // Warm-start deep link (app already running in the background).
        for context in URLContexts {
            NoorLinkForwarder.shared.forward(context.url.absoluteString)
        }
    }

    // MARK: - Helpers

    private func attachForwarder() {
        if let controller = window?.rootViewController as? FlutterViewController {
            NoorLinkForwarder.shared.attach(messenger: controller.binaryMessenger)
        }
    }
}
