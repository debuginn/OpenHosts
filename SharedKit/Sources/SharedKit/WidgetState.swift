import Foundation

public struct WidgetConfigItem: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var isGroup: Bool

    public init(id: UUID, name: String, isEnabled: Bool, isGroup: Bool) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.isGroup = isGroup
    }
}

public struct WidgetState: Codable, Sendable {
    public var items: [WidgetConfigItem]

    public init(items: [WidgetConfigItem]) {
        self.items = items
    }

    public static func read() -> WidgetState? {
        guard let data = try? Data(contentsOf: AppGroup.widgetStateURL) else { return nil }
        return try? JSONDecoder().decode(WidgetState.self, from: data)
    }

    public static func write(_ state: WidgetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: AppGroup.widgetStateURL, options: .atomic)
    }

    public static func toggleItem(_ id: UUID) {
        guard var state = read() else { return }
        guard let idx = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[idx].isEnabled.toggle()
        write(state)
    }
}
