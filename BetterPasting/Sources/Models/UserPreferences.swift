import Foundation

struct UserPreferences: Codable, Sendable {
    // Retention settings
    var maxItemCount: Int = 10_000
    var maxAgeDays: Int = 90

    // Behavior
    var excludedBundleIDs: [String] = []
    var playSoundOnCopy: Bool = false

    /// Fetch page metadata for copied URLs to show a rich preview.
    /// Turning this off stops all outbound network requests.
    var enableLinkPreviews: Bool = true

    // UI
    var showInMenuBar: Bool = true

    init() {}

    // MARK: - Codable
    // Decoded field-by-field so preferences saved by an older build (missing newer
    // keys) still load instead of falling back to all defaults.

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserPreferences()

        maxItemCount = try container.decodeIfPresent(Int.self, forKey: .maxItemCount) ?? defaults.maxItemCount
        maxAgeDays = try container.decodeIfPresent(Int.self, forKey: .maxAgeDays) ?? defaults.maxAgeDays
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        playSoundOnCopy = try container.decodeIfPresent(Bool.self, forKey: .playSoundOnCopy) ?? defaults.playSoundOnCopy
        enableLinkPreviews = try container.decodeIfPresent(Bool.self, forKey: .enableLinkPreviews) ?? defaults.enableLinkPreviews
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? defaults.showInMenuBar
    }

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
