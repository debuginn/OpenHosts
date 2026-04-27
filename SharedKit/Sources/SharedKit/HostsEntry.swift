import Foundation

public struct HostsEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var ip: String
    public var hostname: String
    public var isComment: Bool
    public var isEnabled: Bool

    public init(id: UUID = UUID(), ip: String, hostname: String,
                isComment: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.isComment = isComment
        self.isEnabled = isEnabled
    }
}
