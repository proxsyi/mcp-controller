import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
