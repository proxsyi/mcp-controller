import SwiftUI

@main
struct MCPControllerApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var settings = AppSettings()
    @StateObject private var updates = UpdateManager()
    @StateObject private var settingsWindow = SettingsWindowCoordinator()

    var body: some Scene {
        WindowGroup("MCP Controller") {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updates)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    appDelegate.model = model
                    updates.beginAutomaticChecks()
                    if settings.oneAIOnly { model.applyGlobalOneAIPolicy(true) }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SettingsToggleCommands(coordinator: settingsWindow) }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updates)
                .background(SettingsWindowProbe { settingsWindow.register($0) })
        }

        MenuBarExtra("", systemImage: model.runningCount > 0 ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle") {
            MenuBarView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
