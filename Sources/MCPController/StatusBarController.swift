import SwiftUI
import AppKit
import Combine

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
        let count = model.runningCount
        let activeCount = model.activeCount
        let hasLiveActivity = count > 0 || activeCount > 0
        button.image = NSImage(systemSymbolName: hasLiveActivity ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle", accessibilityDescription: "MCP Controller")
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString(string: "")
        button.title = count > 0 ? " \(count)" : ""
        button.toolTip = tooltip(runningCount: count, activeCount: activeCount, failedCount: model.failedCount)
        statusItem.length = NSStatusItem.variableLength
    }

    private func tooltip(runningCount: Int, activeCount: Int, failedCount: Int) -> String {
        if runningCount == 0 {
            if failedCount > 0 {
                return "MCP Controller — no servers running, \(failedCount) failed"
            }
            if activeCount > 0 {
                return "MCP Controller — starting or stopping \(activeCount) servers"
            }
            return "MCP Controller — no servers running"
        }
        if failedCount > 0 {
            return "MCP Controller — \(runningCount) running, \(failedCount) failed"
        }
        return "MCP Controller — \(runningCount) servers running"
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
