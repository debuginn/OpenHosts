import Foundation
import SwiftUI
import SharedKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var state: AppState
    @Published var isApplyingHosts = false
    @Published var lastError: String?

    private let store: HostsStore
    private let helperClient: HelperXPCClient

    init(store: HostsStore = HostsStore(),
         helperClient: HelperXPCClient = HelperXPCClient()) {
        self.store = store
        self.helperClient = helperClient
        self.state = store.load()
        observeAppGroupChanges()
        Task { try? HelperInstaller.installIfNeeded() }
    }

    // MARK: - Module mode

    func toggleModule(_ id: UUID) {
        guard let idx = state.modules.firstIndex(where: { $0.id == id }) else { return }
        state.modules[idx].isEnabled.toggle()
        persist()
    }

    func addModule(name: String) {
        state.modules.append(HostsGroup(name: name))
        persist()
    }

    func deleteModule(_ id: UUID) {
        state.modules.removeAll { $0.id == id }
        persist()
    }

    func updateModule(_ group: HostsGroup) {
        guard let idx = state.modules.firstIndex(where: { $0.id == group.id }) else { return }
        state.modules[idx] = group
        persist()
    }

    // MARK: - Profile mode

    func activateProfile(_ id: UUID?) {
        state.activeProfileId = id
        persist()
    }

    func addProfile(name: String) {
        state.profiles.append(Profile(name: name))
        persist()
    }

    func deleteProfile(_ id: UUID) {
        state.profiles.removeAll { $0.id == id }
        if state.activeProfileId == id { state.activeProfileId = nil }
        persist()
    }

    func updateProfile(_ profile: Profile) {
        guard let idx = state.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        state.profiles[idx] = profile
        persist()
    }

    // MARK: - Apply

    func applyHosts() async {
        isApplyingHosts = true
        lastError = nil
        defer { isApplyingHosts = false }
        do {
            let content = HostsComposer.compose(from: state)
            try await helperClient.writeHosts(content)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func persist() {
        try? store.save(state)
        notifyAppGroupChanged()
    }

    private func notifyAppGroupChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroup.darwinNotificationName as CFString),
            nil, nil, true
        )
    }

    private func observeAppGroupChanges() {
        let name = AppGroup.darwinNotificationName as CFString
        NotificationCenter.default.addObserver(
            forName: Notification.Name(AppGroup.darwinNotificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = self.store.load()
                await self.applyHosts()
            }
        }
        // Post from Darwin notification center → bridge to NotificationCenter
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, name, _, _ in
                NotificationCenter.default.post(
                    name: Notification.Name(AppGroup.darwinNotificationName),
                    object: nil
                )
            },
            name,
            nil,
            .deliverImmediately
        )
    }
}
