import Foundation

struct UserPreferences: Codable, Sendable {
    // Retention settings
    var maxItemCount: Int = 10_000
    var maxAgeDays: Int = 30

    // Behavior
    var excludedBundleIDs: [String] = []
    var playSoundOnCopy: Bool = false

    // UI
    var showInMenuBar: Bool = true

    // MARK: - Persistence

    private static let key = "BetterPastingPreferences"

    static func load() -> UserPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserPreferences.key)
        }
    }
}
