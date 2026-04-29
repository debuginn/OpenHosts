import Foundation

struct HostsConfig: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var content: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, content: String = "", isEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.isEnabled = isEnabled
    }
}
