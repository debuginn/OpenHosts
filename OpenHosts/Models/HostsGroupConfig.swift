import Foundation

struct HostsGroupConfig: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var memberIDs: [UUID]
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, memberIDs: [UUID] = [], isEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.isEnabled = isEnabled
    }
}
