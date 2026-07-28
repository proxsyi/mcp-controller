import SwiftUI

@main
struct MCPControllerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MCP Controller") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
        }
        .defaultSize(width: 1040, height: 680)

        MenuBarExtra("MCP Controller", systemImage: model.runningCount > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle") {
            MenuBarView()
                .environmentObject(model)
        }
    }
}
