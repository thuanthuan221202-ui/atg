import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var profiles: [ServerProfile] = [] {
        didSet { save() }
    }
    @Published var activeProfileId: UUID? {
        didSet { save() }
    }

    private let profilesKey = "agyr_saved_profiles_v1"
    private let activeIdKey = "agyr_active_profile_id_v1"

    var activeProfile: ServerProfile? {
        guard let id = activeProfileId else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    init() {
        load()
    }

    func upsertProfile(name: String, baseURL: String, token: String) -> ServerProfile {
        let normalized = PairingParser.normalizeBaseURL(baseURL)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Windows PC" : name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = profiles.firstIndex(where: { $0.baseURL.lowercased() == normalized.lowercased() }) {
            profiles[idx].name = cleanName
            profiles[idx].token = cleanToken
            activeProfileId = profiles[idx].id
            return profiles[idx]
        } else {
            let profile = ServerProfile(name: cleanName, baseURL: normalized, token: cleanToken)
            profiles.insert(profile, at: 0)
            activeProfileId = profile.id
            return profile
        }
    }

    func removeProfile(_ profile: ServerProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id {
            activeProfileId = profiles.first?.id
        }
    }

    func selectProfile(_ profile: ServerProfile) {
        activeProfileId = profile.id
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileId {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeIdKey),
           let uuid = UUID(uuidString: idStr) {
            activeProfileId = uuid
        }
    }
}
