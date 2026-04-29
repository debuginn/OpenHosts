import Foundation

public enum HostsComposer {
    public static let startMarker = "# --- OPENHOSTS_START ---"
    public static let endMarker   = "# --- OPENHOSTS_END ---"

    public static func compose(prefix: String, groups: [HostsGroup], suffix: String) -> String {
        var lines = prefix.components(separatedBy: "\n")

        for group in groups {
            lines.append("")
            if group.isEnabled {
                lines.append("# [Group: \(group.name)]")
                lines.append(contentsOf: group.entries)
            } else {
                lines.append("# [Group: \(group.name)] disabled")
                lines.append(contentsOf: group.entries.map { "# \($0)" })
            }
        }

        lines.append("")
        lines.append(contentsOf: suffix.components(separatedBy: "\n"))
        return lines.joined(separator: "\n")
    }

    public static func appendManagedSection(to content: String) -> String {
        var s = content
        if !s.hasSuffix("\n") { s += "\n" }
        s += "\n\(startMarker)\n\(endMarker)\n"
        return s
    }
}
