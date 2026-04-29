import Foundation

enum HostsComposer {
    static let startMarker = "# --- OPENHOSTS_START ---"
    static let endMarker   = "# --- OPENHOSTS_END ---"

    static func extractBoundaries(from content: String) -> (prefix: String, suffix: String, hasSection: Bool) {
        let lines = content.components(separatedBy: "\n")
        guard
            let si = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == startMarker }),
            let ei = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker }),
            si < ei
        else { return (content, "", false) }
        let prefix = lines[...si].joined(separator: "\n")
        let suffix = lines[ei...].joined(separator: "\n")
        return (prefix, suffix, true)
    }

    static func compose(prefix: String, configs: [HostsConfig], suffix: String) -> String {
        var result = prefix
        for config in configs {
            let trimmed = config.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result += "\n# \(config.name)\n" + trimmed
            }
        }
        result += "\n" + suffix
        return result
    }

    static func ensureSection(in content: String) -> String {
        let (_, _, has) = extractBoundaries(from: content)
        if has { return content }
        var s = content
        if !s.hasSuffix("\n") { s += "\n" }
        s += "\n\(startMarker)\n\(endMarker)\n"
        return s
    }
}
