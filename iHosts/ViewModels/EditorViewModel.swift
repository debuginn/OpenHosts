import Foundation
import SharedKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var content: String
    @Published var isDirty = false

    private let originalContent: String

    init(group: HostsGroup) {
        let text = group.entries.map { entry -> String in
            if entry.isComment { return "# \(entry.hostname)" }
            let prefix = entry.isEnabled ? "" : "# "
            return "\(prefix)\(entry.ip)\t\(entry.hostname)"
        }.joined(separator: "\n")
        self.content = text
        self.originalContent = text
    }

    func markDirty() {
        isDirty = content != originalContent
    }

    func parse() -> [HostsEntry] {
        content.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }

            if trimmed.hasPrefix("#") {
                let comment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let parts = comment.split(separator: " ", maxSplits: 1)
                if parts.count == 2, isValidIP(String(parts[0])) {
                    return HostsEntry(ip: String(parts[0]),
                                      hostname: String(parts[1]),
                                      isEnabled: false)
                }
                return HostsEntry(ip: "", hostname: comment, isComment: true)
            }

            let parts = trimmed.split(maxSplits: 2,
                                       whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { return nil }
            return HostsEntry(ip: String(parts[0]), hostname: String(parts[1]))
        }
    }

    func save(to group: inout HostsGroup) {
        group.entries = parse()
        isDirty = false
    }

    private func isValidIP(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
