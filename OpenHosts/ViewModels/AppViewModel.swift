import Foundation
import SwiftUI
import ServiceManagement
import OSLog
import Combine

private let log = Logger(subsystem: "com.debuginn.OpenHosts", category: "AppViewModel")

@MainActor
final class AppViewModel: ObservableObject {

    enum SidebarItem: Hashable, Sendable {
        case systemHosts
        case config(UUID)
        case group(UUID)
    }

    enum ApplyState: Equatable {
        case idle, applying, success, failure(String)
    }

    @Published var configs: [HostsConfig] = []
    @Published var groups: [HostsGroupConfig] = []
    @Published var selectedItem: SidebarItem? = .systemHosts
    @Published var systemHostsContent: String = ""
    @Published var applyState: ApplyState = .idle
    @Published var helperStatus: SMAppService.Status = .notRegistered
    @Published var helperRegistrationError: String?
    @Published var validationFailedConfigID: UUID?

    private let store = ConfigStore.shared
    private let helperClient = HelperXPCClient()
    private var cancellables = Set<AnyCancellable>()
    private let contentSubject = PassthroughSubject<UUID, Never>()
    private var lastSavedContent: [UUID: String] = [:]

    init() {
        helperStatus = HelperInstaller.status
        log.info("init: helperStatus=\(self.helperStatus.debugDescription)")
        loadAll()
        if helperStatus == .notRegistered {
            Task { await registerHelper() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshHelperStatus() }
        }
        contentSubject
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] id in
                guard let self else { return }
                if let config = self.configs.first(where: { $0.id == id }) {
                    let prev = self.lastSavedContent[id]
                    if prev != nil && prev != config.content {
                        self.captureSnapshot(for: config)
                    }
                    self.lastSavedContent[id] = config.content
                }
                self.store.save(self.configs)
                if self.configs.first(where: { $0.id == id })?.isEnabled == true {
                    Task { await self.reapply() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func loadAll() {
        configs = store.load()
        groups = store.loadGroups()
        loadSystemHosts()
        for config in configs {
            lastSavedContent[config.id] = config.content
        }
    }

    func loadSystemHosts() {
        systemHostsContent = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
    }

    // MARK: - Config management

    func addConfig(name: String) {
        let config = HostsConfig(name: name)
        configs.append(config)
        store.save(configs)
        selectedItem = .config(config.id)
    }

    func deleteConfig(_ id: UUID) {
        let wasReferenced = configs.first(where: { $0.id == id })?.isEnabled == true
            || groups.contains(where: { $0.isEnabled && $0.memberIDs.contains(id) })
        if case .config(let sel) = selectedItem, sel == id { selectedItem = .systemHosts }
        configs.removeAll { $0.id == id }
        store.save(configs)
        store.clearSnapshots(for: id)
        lastSavedContent.removeValue(forKey: id)
        for i in groups.indices {
            groups[i].memberIDs.removeAll { $0 == id }
        }
        store.saveGroups(groups)
        if wasReferenced { Task { await reapply() } }
    }

    func updateConfigContent(_ id: UUID, content: String) {
        guard let idx = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[idx].content = content
        contentSubject.send(id)
    }

    func renameConfig(_ id: UUID, to name: String) {
        guard let idx = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[idx].name = name
        store.save(configs)
        if configs[idx].isEnabled { Task { await reapply() } }
    }

    func toggleConfig(_ id: UUID) {
        guard let idx = configs.firstIndex(where: { $0.id == id }) else { return }
        if !configs[idx].isEnabled && !HostsValidator.validateContent(configs[idx].content) {
            validationFailedConfigID = id
            Task {
                try? await Task.sleep(for: .seconds(2))
                if validationFailedConfigID == id { validationFailedConfigID = nil }
            }
            return
        }
        validationFailedConfigID = nil
        configs[idx].isEnabled.toggle()
        store.save(configs)
        Task { await reapply() }
    }

    // MARK: - Group management

    func addGroup(name: String, memberIDs: [UUID]) {
        let group = HostsGroupConfig(name: name, memberIDs: memberIDs)
        groups.append(group)
        store.saveGroups(groups)
        selectedItem = .group(group.id)
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].name = name
        store.saveGroups(groups)
    }

    func deleteGroup(_ id: UUID) {
        let wasEnabled = groups.first(where: { $0.id == id })?.isEnabled ?? false
        if case .group(let sel) = selectedItem, sel == id { selectedItem = .systemHosts }
        groups.removeAll { $0.id == id }
        store.saveGroups(groups)
        if wasEnabled { Task { await reapply() } }
    }

    func toggleGroup(_ id: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        if !groups[idx].isEnabled {
            let memberConfigs = configs.filter { groups[idx].memberIDs.contains($0.id) }
            if let bad = memberConfigs.first(where: { !HostsValidator.validateContent($0.content) }) {
                validationFailedConfigID = bad.id
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if validationFailedConfigID == bad.id { validationFailedConfigID = nil }
                }
                return
            }
        }
        validationFailedConfigID = nil
        groups[idx].isEnabled.toggle()
        store.saveGroups(groups)
        Task { await reapply() }
    }

    func updateGroupMembers(_ id: UUID, memberIDs: [UUID]) {
        guard let idx = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[idx].memberIDs = memberIDs
        store.saveGroups(groups)
        if groups[idx].isEnabled { Task { await reapply() } }
    }

    // MARK: - Snapshots

    private func captureSnapshot(for config: HostsConfig) {
        let snapshot = ConfigSnapshot(
            configID: config.id,
            content: config.content,
            createdAt: Date()
        )
        store.saveSnapshot(snapshot)
    }

    func loadSnapshots(for configID: UUID) -> [ConfigSnapshot] {
        store.loadSnapshots(for: configID)
    }

    func loadAllSnapshots() -> [ConfigSnapshot] {
        store.loadAllConfigSnapshots()
    }

    func restoreSnapshot(_ snapshot: ConfigSnapshot) {
        guard let idx = configs.firstIndex(where: { $0.id == snapshot.configID }) else { return }
        configs[idx].content = snapshot.content
        lastSavedContent[snapshot.configID] = snapshot.content
        store.save(configs)
        if configs[idx].isEnabled { Task { await reapply() } }
    }

    var effectiveConfigs: [HostsConfig] {
        let groupMemberIDs: Set<UUID> = groups
            .filter(\.isEnabled)
            .reduce(into: Set<UUID>()) { $0.formUnion($1.memberIDs) }
        var seen = Set<UUID>()
        return configs.filter { config in
            guard !seen.contains(config.id) else { return false }
            seen.insert(config.id)
            return config.isEnabled || groupMemberIDs.contains(config.id)
        }
    }

    // MARK: - Apply

    private func reapply() async {
        guard helperStatus == .enabled else { return }
        let current = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
        let withSection = HostsComposer.ensureSection(in: current)
        let (prefix, suffix, _) = HostsComposer.extractBoundaries(from: withSection)
        let composed = HostsComposer.compose(prefix: prefix, configs: effectiveConfigs, suffix: suffix)
        applyState = .applying
        do {
            try await helperClient.writeHosts(composed)
            applyState = .success
            loadSystemHosts()
            log.info("reapply succeeded")
            try? await Task.sleep(for: .seconds(2))
            if applyState == .success { applyState = .idle }
        } catch {
            applyState = .failure(error.localizedDescription)
            log.error("reapply failed: \(error)")
        }
    }

    // MARK: - Dock Visibility

    @AppStorage("showInDock") var showInDock: Bool = true

    // MARK: - Launch at Login

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
        } catch {
            log.error("setLaunchAtLogin failed: \(error)")
        }
    }

    // MARK: - Helper

    func refreshHelperStatus() {
        let s = HelperInstaller.status
        log.info("refreshHelperStatus: \(s.debugDescription)")
        helperStatus = s
    }

    func retryInstall() {
        let current = HelperInstaller.status
        if current == .requiresApproval {
            HelperInstaller.openSystemSettings()
            return
        }
        Task { await registerHelper() }
    }

    func openSystemSettings() { HelperInstaller.openSystemSettings() }

    private func registerHelper() async {
        do {
            try HelperInstaller.registerIfNeeded()
            let s = HelperInstaller.status
            helperStatus = s
            helperRegistrationError = nil
            log.info("registerHelper done: \(s.debugDescription)")
        } catch {
            helperStatus = HelperInstaller.status
            let msg = Self.friendlyHelperError(error)
            helperRegistrationError = msg
            log.error("registerHelper failed: \(msg)")
        }
    }

    private static func friendlyHelperError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == "SMAppServiceErrorDomain" {
            switch ns.code {
            case 1: return "Code signing issue: app must be signed with a Developer certificate."
            case 2, 9: return "Move OpenHosts to /Applications and relaunch."
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain && ns.code == 22 {
            return "Move OpenHosts to /Applications and relaunch."
        }
        return "[\(ns.domain) \(ns.code)] \(ns.localizedDescription)"
    }
}

private extension SMAppService.Status {
    var debugDescription: String {
        switch self {
        case .notRegistered:    return "notRegistered"
        case .enabled:          return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound:         return "notFound"
        @unknown default:       return "unknown(\(rawValue))"
        }
    }
}
