import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false
    private var isDuplicateLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) else { return }

        isDuplicateLaunch = true
        existing.activate(options: [.activateAllWindows])
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
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
