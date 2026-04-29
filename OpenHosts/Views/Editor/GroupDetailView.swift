import SwiftUI

struct GroupDetailView: View {
    @EnvironmentObject var vm: AppViewModel
    let groupID: UUID

    private var group: HostsGroupConfig? {
        vm.groups.first(where: { $0.id == groupID })
    }

    var body: some View {
        if let group {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Members")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(vm.configs) { config in
                            let isMember = group.memberIDs.contains(config.id)
                            Button {
                                var ids = group.memberIDs
                                if isMember { ids.removeAll { $0 == config.id } }
                                else { ids.append(config.id) }
                                vm.updateGroupMembers(groupID, memberIDs: ids)
                            } label: {
                                Label(config.name, systemImage: "doc.text")
                                    .font(.callout)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(isMember ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isMember ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .foregroundStyle(isMember ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    let memberConfigs = vm.configs.filter { group.memberIDs.contains($0.id) }
                    let preview = memberConfigs.map(\.content).joined(separator: "\n\n")
                    if preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No entries")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            Text(preview)
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle(group.name)
        } else {
            ContentUnavailableView("Group not found", systemImage: "questionmark")
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i > 0 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for (i, row) in rows.enumerated() {
            if i > 0 { y += spacing }
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for sub in row {
                let size = sub.sizeThatFits(.unspecified)
                sub.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(sub)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
