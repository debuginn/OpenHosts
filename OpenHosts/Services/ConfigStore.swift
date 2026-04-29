import Foundation

@MainActor
final class ConfigStore {
    static let shared = ConfigStore()

    private let configsURL: URL
    private let groupsURL: URL
    private let snapshotsURL: URL
    private let maxSnapshots = 30

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("com.debuginn.OpenHosts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configsURL = dir.appendingPathComponent("configs.json")
        groupsURL = dir.appendingPathComponent("groups.json")
        snapshotsURL = dir.appendingPathComponent("snapshots.json")
    }

    func load() -> [HostsConfig] {
        guard let data = try? Data(contentsOf: configsURL) else { return [] }
        return (try? JSONDecoder().decode([HostsConfig].self, from: data)) ?? []
    }

    func save(_ configs: [HostsConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: configsURL, options: .atomic)
    }

    func loadGroups() -> [HostsGroupConfig] {
        guard let data = try? Data(contentsOf: groupsURL) else { return [] }
        return (try? JSONDecoder().decode([HostsGroupConfig].self, from: data)) ?? []
    }

    func saveGroups(_ groups: [HostsGroupConfig]) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        try? data.write(to: groupsURL, options: .atomic)
    }

    // MARK: - Snapshots

    private func loadAllSnapshots() -> [ConfigSnapshot] {
        guard let data = try? Data(contentsOf: snapshotsURL) else { return [] }
        return (try? JSONDecoder().decode([ConfigSnapshot].self, from: data)) ?? []
    }

    private func saveAllSnapshots(_ snapshots: [ConfigSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: snapshotsURL, options: .atomic)
    }

    func loadSnapshots(for configID: UUID) -> [ConfigSnapshot] {
        loadAllSnapshots()
            .filter { $0.configID == configID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadAllConfigSnapshots() -> [ConfigSnapshot] {
        loadAllSnapshots().sorted { $0.createdAt > $1.createdAt }
    }

    func saveSnapshot(_ snapshot: ConfigSnapshot) {
        var all = loadAllSnapshots()
        all.append(snapshot)
        let forConfig = all.filter { $0.configID == snapshot.configID }
        if forConfig.count > maxSnapshots {
            let oldest = forConfig.sorted { $0.createdAt < $1.createdAt }
            let toRemove = Set(oldest.prefix(forConfig.count - maxSnapshots).map(\.id))
            all.removeAll { toRemove.contains($0.id) }
        }
        saveAllSnapshots(all)
    }

    func clearSnapshots(for configID: UUID) {
        var all = loadAllSnapshots()
        all.removeAll { $0.configID == configID }
        saveAllSnapshots(all)
    }
}
