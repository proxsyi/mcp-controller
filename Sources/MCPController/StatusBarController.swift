import SwiftUI
import AppKit
import Combine

struct StatusBarPresentation: Equatable {
    let symbolName: String
    let title: String
    let tooltip: String

    init(runningCount: Int, activeCount: Int, failedCount: Int) {
        symbolName = runningCount > 0 || activeCount > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
        title = runningCount > 0 ? " \(runningCount)" : ""

        let transitioningCount = max(0, activeCount - runningCount)
        var parts: [String] = []
        if runningCount > 0 {
            parts.append("\(runningCount) running")
        }
        if transitioningCount > 0 {
            parts.append("\(transitioningCount) starting or stopping")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) failed")
        }
        tooltip = parts.isEmpty
            ? "MCP Controller — no servers running"
            : "MCP Controller — " + parts.joined(separator: ", ")
    }
}

struct StatusPanelPresentation {
    static let size = NSSize(width: 390, height: 420)
    static let dismissalEventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
    static let level = NSWindow.Level.popUpMenu
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .transient,
        .ignoresCycle
    ]
}

struct StatusPanelTogglePolicy {
    static func shouldOpen(panelWasVisibleAtMouseDown: Bool, panelIsVisibleNow: Bool) -> Bool {
        !panelWasVisibleAtMouseDown && !panelIsVisibleNow
    }
}

struct StatusPanelDismissalPolicy {
    static func shouldDismiss(
        eventType: NSEvent.EventType,
        keyCode: UInt16,
        isInsidePanel: Bool,
        isInsideStatusItem: Bool
    ) -> Bool {
        if eventType == .keyDown {
            return keyCode == 53
        }
        guard eventType == .leftMouseDown || eventType == .rightMouseDown else { return false }
        return !isInsidePanel && !isInsideStatusItem
    }
}

private final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var observation: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var lastMouseDownEventNumber: Int?
    private var panelWasVisibleAtLastMouseDown = false
    private weak var model: AppModel?

    private lazy var panel: StatusPanel = {
        let panel = StatusPanel(
            contentRect: NSRect(origin: .zero, size: StatusPanelPresentation.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = StatusPanelPresentation.level
        panel.collectionBehavior = StatusPanelPresentation.collectionBehavior
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }()

    func install(model: AppModel) {
        self.model = model
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePanel(_:))
            item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
            statusItem = item
        }
        observation = Publishers.CombineLatest(model.$profiles, model.$phases)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak model] _, _ in
                guard let self, let model, self.model === model else { return }
                self.refresh(using: model)
            }
        refresh(using: model)
    }

    private func refresh(using model: AppModel) {
        hostingController.rootView = AnyView(
            MenuBarView()
                .environmentObject(model)
                .background(.regularMaterial)
        )
        updateButton(using: model)
    }

    private func updateButton(using model: AppModel) {
        guard let statusItem, let button = statusItem.button else { return }
        let presentation = StatusBarPresentation(
            runningCount: model.runningCount,
            activeCount: model.activeCount,
            failedCount: model.failedCount
        )
        button.image = NSImage(systemSymbolName: presentation.symbolName, accessibilityDescription: "MCP Controller")
        button.imagePosition = .imageLeading
        button.title = presentation.title
        button.toolTip = presentation.tooltip
        statusItem.length = NSStatusItem.variableLength
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        let currentEventNumber = NSApplication.shared.currentEvent?.eventNumber
        let panelWasVisibleAtMouseDown = currentEventNumber == lastMouseDownEventNumber
            ? panelWasVisibleAtLastMouseDown
            : panel.isVisible
        lastMouseDownEventNumber = nil
        panelWasVisibleAtLastMouseDown = false

        if StatusPanelTogglePolicy.shouldOpen(
            panelWasVisibleAtMouseDown: panelWasVisibleAtMouseDown,
            panelIsVisibleNow: panel.isVisible
        ) {
            showPanel(relativeTo: button)
        } else {
            hidePanel(sender)
        }
    }

    private func showPanel(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = buttonWindow.convertToScreen(buttonFrameInWindow)
        let panelSize = StatusPanelPresentation.size
        var origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - 6
        )

        if let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
            origin.y = max(origin.y, visibleFrame.minY + 8)
        }

        panel.setContentSize(panelSize)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        installDismissalMonitors()
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: StatusPanelPresentation.dismissalEventMask
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.lastMouseDownEventNumber = event.eventNumber
                self.panelWasVisibleAtLastMouseDown = true
            }
            let isInsidePanel = event.window === self.panel
            let isInsideStatusItem = self.isInsideStatusItem(event)
            guard StatusPanelDismissalPolicy.shouldDismiss(
                eventType: event.type,
                keyCode: event.keyCode,
                isInsidePanel: isInsidePanel,
                isInsideStatusItem: isInsideStatusItem
            ) else { return event }
            self.hidePanel()
            return event.type == .keyDown ? nil : event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hidePanel()
            }
        }
    }

    private func isInsideStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              event.window === buttonWindow else { return false }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func hidePanel(_ sender: Any? = nil) {
        panel.orderOut(sender)
        removeDismissalMonitors()
    }

    private func removeDismissalMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}
