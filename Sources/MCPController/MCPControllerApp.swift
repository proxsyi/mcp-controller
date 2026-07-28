import SwiftUI

@main
struct MCPControllerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("MCP Controller") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra("", systemImage: model.runningCount > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle") {
            MenuBarView()
                .environmentObject(model)
        }
    }
}
