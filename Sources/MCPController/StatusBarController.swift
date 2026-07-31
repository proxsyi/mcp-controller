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
        guard let button = statusItem?.button else { return }
        let count = model.runningCount
        button.image = NSImage(systemSymbolName: count > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle", accessibilityDescription: "MCP Controller")
        button.imagePosition = .imageLeft
        button.title = count > 0 ? " \(count)" : ""
        button.toolTip = count == 0 ? "MCP Controller — no servers running" : "MCP Controller — \(count) servers running"
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
