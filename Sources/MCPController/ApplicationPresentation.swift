import SwiftUI
import AppKit

enum ApplicationPresentationPolicy {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("mainWindow")
    static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("settingsWindow")
    static let statusPopoverWindowIdentifier = NSUserInterfaceItemIdentifier("statusPopoverWindow")

    static func activationPolicy(hasOpenMainWindow: Bool) -> NSApplication.ActivationPolicy {
        hasOpenMainWindow ? .regular : .accessory
    }
}

@MainActor
final class MainWindowCoordinator: ObservableObject {
    static let shared = MainWindowCoordinator()

    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var hasOpenMainWindow = false
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Bool
    private let activateApp: () -> Void

    init(
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = { NSApplication.shared.setActivationPolicy($0) },
        activateApp: @escaping () -> Void = { _ = NSRunningApplication.current.activate(options: [.activateAllWindows]) }
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.activateApp = activateApp
    }

    func register(_ window: NSWindow) {
        if self.window !== window {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()

            self.window = window
            window.identifier = ApplicationPresentationPolicy.mainWindowIdentifier
            window.title = "MCP Controller"
            window.isReleasedWhenClosed = false

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.markWindowOpen() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.markWindowOpen() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.markWindowOpen() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleWindowWillClose() }
            })
        }

        hasOpenMainWindow = true
        syncActivationPolicy()
    }

    @discardableResult
    func presentMainWindow() -> Bool {
        guard let window else { return false }
        hasOpenMainWindow = true
        showDockIcon()
        activateApp()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()
        return true
    }

    func toggleMainWindow(openWindow: (() -> Void)? = nil) {
        if isVisibleAndUnminimized {
            closeMainWindow()
            return
        }

        if presentMainWindow() {
            return
        }

        showDockIcon()
        openWindow?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            _ = self?.presentMainWindow()
        }
    }

    func closeMainWindow() {
        guard hasOpenMainWindow, let window else { return }
        window.performClose(nil)
    }

    func syncActivationPolicy() {
        _ = setActivationPolicy(ApplicationPresentationPolicy.activationPolicy(hasOpenMainWindow: hasOpenMainWindow))
    }

    private var isVisibleAndUnminimized: Bool {
        guard let window else { return false }
        return hasOpenMainWindow && window.isVisible && !window.isMiniaturized
    }

    private func markWindowOpen() {
        hasOpenMainWindow = true
        showDockIcon()
    }

    private func handleWindowWillClose() {
        hasOpenMainWindow = false
        hideDockIcon()
    }

    private func showDockIcon() {
        _ = setActivationPolicy(.regular)
    }

    private func hideDockIcon() {
        _ = setActivationPolicy(.accessory)
    }
}

final class MainWindowProbeView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}

struct MainWindowProbe: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> MainWindowProbeView {
        let view = MainWindowProbeView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: MainWindowProbeView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }
}
