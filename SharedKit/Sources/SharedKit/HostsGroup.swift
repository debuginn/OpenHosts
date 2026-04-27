import Foundation

public struct HostsGroup: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var entries: [HostsEntry]

    public init(id: UUID = UUID(), name: String,
                isEnabled: Bool = true, entries: [HostsEntry] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.entries = entries
    }
}
