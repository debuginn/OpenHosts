import Foundation

public struct Profile: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var groups: [HostsGroup]

    public init(id: UUID = UUID(), name: String, groups: [HostsGroup] = []) {
        self.id = id
        self.name = name
        self.groups = groups
    }
}
