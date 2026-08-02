import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static weak var shared: AppSettings?

    private enum Key {
        static let oneAIOnly = "settings.oneAIOnly"
        static let preferredSettingsSection = "settings.preferredSettingsSection"
    }

    @Published var oneAIOnly: Bool {
        didSet { UserDefaults.standard.set(oneAIOnly, forKey: Key.oneAIOnly) }
    }

    @Published var preferredSettingsSection: String {
        didSet { UserDefaults.standard.set(preferredSettingsSection, forKey: Key.preferredSettingsSection) }
    }

    init() {
        oneAIOnly = UserDefaults.standard.bool(forKey: Key.oneAIOnly)
        preferredSettingsSection = UserDefaults.standard.string(forKey: Key.preferredSettingsSection) ?? "app"
        Self.shared = self
    }
}
