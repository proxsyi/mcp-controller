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

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private var observation: AnyCancellable?
    private weak var model: AppModel?

    func install(model: AppModel) {
        self.model = model
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        }
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 390, height: 420)
        popover.contentViewController = hostingController
        observation = Publishers.CombineLatest(model.$profiles, model.$phases)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak model] _, _ in
                guard let self, let model, self.model === model else { return }
                self.refresh(using: model)
            }
        refresh(using: model)
    }

    private func refresh(using model: AppModel) {
        hostingController.rootView = AnyView(MenuBarView().environmentObject(model))
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
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            configurePopoverWindowForCurrentSpace()
        }
    }

    private func configurePopoverWindowForCurrentSpace() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.level = .popUpMenu
        window.hidesOnDeactivate = false
        window.collectionBehavior.formUnion([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ])
        window.orderFrontRegardless()
        window.makeKey()
    }
}
