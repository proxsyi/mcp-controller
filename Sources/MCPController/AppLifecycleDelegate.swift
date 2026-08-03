import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false
    private var isDuplicateLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        ApplicationLifetimePolicy.keepControllerAvailable()
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else { return }

        isDuplicateLaunch = true
        existing.activate()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainWindowCoordinator.shared.syncActivationPolicy()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if MainWindowCoordinator.shared.presentMainWindow() {
            return true
        }
        presentMainWindow(in: sender)
        return true
    }

    private func presentMainWindow(in application: NSApplication) {
        application.activate(ignoringOtherApps: true)

        let candidate = application.windows.first(where: {
            $0.identifier == ApplicationPresentationPolicy.mainWindowIdentifier
        })
        guard let window = candidate else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isDuplicateLaunch { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task { @MainActor in
            await AppModel.shared?.shutdownForApplicationQuit()
            sender.reply(toApplicationShouldTerminate: true)
            self.isTerminating = false
        }
        return .terminateLater
    }
}
