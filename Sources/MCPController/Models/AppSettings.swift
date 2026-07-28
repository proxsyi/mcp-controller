import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let oneAIOnly = "settings.oneAIOnly"
    }

    @Published var oneAIOnly: Bool {
        didSet { UserDefaults.standard.set(oneAIOnly, forKey: Key.oneAIOnly) }
    }

    init() {
        oneAIOnly = UserDefaults.standard.bool(forKey: Key.oneAIOnly)
    }
}
