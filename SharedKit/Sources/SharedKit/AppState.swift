import Foundation

public struct AppState: Codable, Sendable, Equatable {
    public var modules: [HostsGroup]
    public var profiles: [Profile]
    public var activeProfileId: UUID?
    public var systemHostsHeader: String

    public init(modules: [HostsGroup] = [],
                profiles: [Profile] = [],
                activeProfileId: UUID? = nil,
                systemHostsHeader: String = "") {
        self.modules = modules
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.systemHostsHeader = systemHostsHeader
    }

    public static let empty = AppState()
}
