import SwiftUI

@main
@MainActor
struct MCPControllerApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var model: AppModel
    @StateObject private var settings: AppSettings
    @StateObject private var updates: UpdateManager
    @StateObject private var settingsWindow: SettingsWindowCoordinator
    @StateObject private var statusBar: StatusBarController

    init() {
        let model = AppModel()
        let settings = AppSettings()
        let updates = UpdateManager()
        let settingsWindow = SettingsWindowCoordinator()
        let statusBar = StatusBarController()
        statusBar.install(model: model)
        model.onShowSettings = nil
        model.onCheckForUpdates = {
            updates.checkForUpdates()
            return updates.statusMessage.isEmpty ? "Checking GitHub…" : updates.statusMessage
        }
        model.onInstallUpdate = {
            if !updates.updateAvailable { updates.checkForUpdates() }
            if updates.updateAvailable { updates.installAvailableUpdate() }
            return updates.statusMessage.isEmpty ? "Installing update…" : updates.statusMessage
        }
        updates.beginAutomaticChecks()
        _model = StateObject(wrappedValue: model)
        _settings = StateObject(wrappedValue: settings)
        _updates = StateObject(wrappedValue: updates)
        _settingsWindow = StateObject(wrappedValue: settingsWindow)
        _statusBar = StateObject(wrappedValue: statusBar)
    }

    var body: some Scene {
        WindowGroup("MCP Controller") {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updates)
                .frame(minWidth: 980, minHeight: 640)
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
    }
}
