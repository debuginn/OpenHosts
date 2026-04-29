import SwiftUI

struct HistoryInspectorView: View {
    @EnvironmentObject var vm: AppViewModel

    @State private var snapshots: [ConfigSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if snapshots.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("Edit a config to create history"))
            } else {
                List {
                    ForEach(snapshots) { snapshot in
                        snapshotRow(snapshot)
                    }
                }
                .listStyle(.plain)

                Divider()

                Text("\(snapshots.count) \(snapshots.count == 1 ? "version" : "versions")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .onAppear { reload() }
        .onChange(of: vm.configs.map(\.id)) { reload() }
    }

    private func reload() {
        snapshots = vm.loadAllSnapshots()
    }

    private func snapshotRow(_ snapshot: ConfigSnapshot) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                if let name = vm.configs.first(where: { $0.id == snapshot.configID })?.name {
                    Text(name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                Text(snapshot.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(summaryText(snapshot.content))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Restore") {
                vm.restoreSnapshot(snapshot)
                reload()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .font(.caption2)
        }
        .padding(.vertical, 2)
    }

    private func summaryText(_ content: String) -> String {
        let line = content
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        return line ?? "(empty)"
    }
}
