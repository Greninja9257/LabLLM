import AppKit

/// Handles Cmd+Q / Quit gracefully: if a training run is active, stop it and wait
/// (bounded) for the in-flight checkpoint save to finish before actually quitting,
/// so closing the app doesn't lose progress.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var trainer: Trainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in self?.activateMainWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateMainWindow()
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let trainer = trainer, trainer.isTraining else { return .terminateNow }

        DispatchQueue.global(qos: .userInitiated).async {
            _ = trainer.requestGracefulShutdown(timeout: 8)
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}
