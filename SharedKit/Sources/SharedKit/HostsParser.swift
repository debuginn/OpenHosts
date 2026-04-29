import Foundation

public struct ParsedHosts: Sendable {
    public var prefix: String
    public var groups: [HostsGroup]
    public var suffix: String
    public var hasManagedSection: Bool
}

public enum HostsParser {
    static let startMarker = "# --- OPENHOSTS_START ---"
    static let endMarker   = "# --- OPENHOSTS_END ---"
    static let groupPrefix = "# [Group: "

    public static func parse(_ content: String) -> ParsedHosts {
        let lines = content.components(separatedBy: "\n")

        guard
            let si = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == startMarker }),
            let ei = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker }),
            si < ei
        else {
            return ParsedHosts(prefix: content, groups: [], suffix: "", hasManagedSection: false)
        }

        let prefix = lines[...si].joined(separator: "\n")
        let suffix = lines[ei...].joined(separator: "\n")
        let managed = Array(lines[(si + 1)..<ei])

        var groups: [HostsGroup] = []
        var current: HostsGroup? = nil

        for line in managed {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(groupPrefix) {
                if let g = current { groups.append(g) }
                let isDisabled = t.hasSuffix("] disabled")
                let inner = String(t.dropFirst(groupPrefix.count))
                let name = isDisabled
                    ? String(inner.dropLast(" disabled".count + 1))  // drop "] disabled"
                    : String(inner.dropLast())                        // drop "]"
                current = HostsGroup(name: name, isEnabled: !isDisabled)
            } else if var g = current {
                if t.isEmpty { continue }
                if g.isEnabled {
                    if !t.hasPrefix("#") {
                        g.entries.append(line)
                        current = g
                    }
                } else if t.hasPrefix("# ") {
                    g.entries.append(String(t.dropFirst(2)))
                    current = g
                }
            }
        }
        if let g = current { groups.append(g) }

        return ParsedHosts(prefix: prefix, groups: groups, suffix: suffix, hasManagedSection: true)
    }
}
