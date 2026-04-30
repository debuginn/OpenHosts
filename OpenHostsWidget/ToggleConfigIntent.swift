import AppIntents
import SharedKit

struct ToggleConfigIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Config"
    static let description: IntentDescription = "Toggle a hosts config or group on/off"

    @Parameter(title: "Item ID")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: itemID) else { return .result() }
        WidgetState.toggleItem(uuid)
        AppGroup.postDarwinNotification()
        return .result()
    }
}
