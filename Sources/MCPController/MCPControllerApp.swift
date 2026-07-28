import SwiftUI

@main
struct MCPControllerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateManager()

    var body: some Scene {
        WindowGroup("MCP Controller") {
            RootView()
                .environmentObject(model)
                .environmentObject(updates)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { updates.beginAutomaticChecks() }
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra("", systemImage: model.runningCount > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
