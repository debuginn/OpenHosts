import Foundation

public struct HostsGroup: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var entries: [String]
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, entries: [String] = [], isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.entries = entries
        self.isEnabled = isEnabled
    }
}
