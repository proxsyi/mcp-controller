import SwiftUI
import AppKit

@MainActor
final class SettingsWindowCoordinator: ObservableObject {
    private weak var window: NSWindow?
    private var visibleSince: Date?
    private var observers: [NSObjectProtocol] = []

    func register(_ window: NSWindow) {
        guard self.window !== window else {
            if window.isVisible && visibleSince == nil { visibleSince = Date() }
            return
        }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        self.window = window
        window.identifier = ApplicationPresentationPolicy.settingsWindowIdentifier
        window.title = "MCP Controller Settings"
        window.isReleasedWhenClosed = false
        if window.isVisible { visibleSince = Date() }

        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if self?.visibleSince == nil { self?.visibleSince = Date() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.visibleSince = nil }
        })
    }

    func handleSettingsShortcut() -> Bool {
        guard let window, window.isVisible else {
            visibleSince = nil
            return false
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let age = Date().timeIntervalSince(visibleSince ?? Date())
        guard age >= 0.5 else { return true }
        window.close()
        visibleSince = nil
        return true
    }
}

final class SettingsWindowProbeView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindow?(window) }
    }
}

struct SettingsWindowProbe: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> SettingsWindowProbeView {
        let view = SettingsWindowProbeView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: SettingsWindowProbeView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window { onWindow(window) }
    }
}

struct SettingsToggleCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var coordinator: SettingsWindowCoordinator

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                if !coordinator.handleSettingsShortcut() {
                    AppSettings.shared?.preferredSettingsSection = "app"
                    openSettings()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
