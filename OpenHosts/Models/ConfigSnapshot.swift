import Foundation

struct ConfigSnapshot: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var configID: UUID
    var content: String
    var createdAt: Date
}
