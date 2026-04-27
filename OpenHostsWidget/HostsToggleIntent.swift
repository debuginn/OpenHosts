import AppIntents
import WidgetKit
import SharedKit

struct ToggleModuleIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Toggle Hosts Module"

    @Parameter(title: "Module ID")
    var moduleID: String

    init() {}
    init(moduleID: String) { self.moduleID = moduleID }

    func perform() async throws -> some IntentResult {
        let store = HostsStore()
        var state = store.load()

        guard let id = UUID(uuidString: moduleID),
              let idx = state.modules.firstIndex(where: { $0.id == id }) else {
            return .result()
        }

        state.modules[idx].isEnabled.toggle()
        try store.save(state)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroup.darwinNotificationName as CFString),
            nil, nil, true
        )

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
