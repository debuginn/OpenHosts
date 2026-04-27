import Foundation

public enum HostsComposer {
    public static func compose(from state: AppState) -> String {
        var lines: [String] = []

        if !state.systemHostsHeader.isEmpty {
            lines.append(state.systemHostsHeader)
        }

        let groups: [HostsGroup]
        if let profileId = state.activeProfileId,
           let profile = state.profiles.first(where: { $0.id == profileId }) {
            groups = profile.groups
        } else {
            groups = state.modules
        }

        for group in groups where group.isEnabled {
            for entry in group.entries where entry.isEnabled {
                if entry.isComment {
                    lines.append("# \(entry.hostname)")
                } else {
                    lines.append("\(entry.ip)\t\(entry.hostname)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
