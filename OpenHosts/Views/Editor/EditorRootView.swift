import SwiftUI

struct EditorRootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
        }
        .onAppear { vm.loadAll() }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch vm.selectedItem {
        case .systemHosts, nil:
            SystemHostsDetailView()
        case .config(let id):
            ConfigDetailView(configID: id)
                .id(id)
        case .group(let id):
            GroupDetailView(groupID: id)
                .id(id)
        }
    }
}

// MARK: - /etc/hosts (read-only)

private struct SystemHostsDetailView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HostsEditorView(
                text: Binding(get: { vm.systemHostsContent }, set: { _ in }),
                isEditable: false
            )
            Divider()
            HStack(spacing: 12) {
                Text("Read Only")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.secondary)
                Spacer()
                let lines = vm.systemHostsContent.components(separatedBy: "\n").count
                Text("\(lines) lines")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let size = vm.systemHostsContent.utf8.count
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .navigationTitle("/etc/hosts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { withAnimation { showingHistory.toggle() } } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                }
                .help("History")
            }
            ToolbarItem(placement: .automatic) {
                helperButton
            }
        }
        .inspector(isPresented: $showingHistory) {
            HistoryInspectorView()
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
    }

    @ViewBuilder
    private var helperButton: some View {
        switch vm.helperStatus {
        case .enabled:
            EmptyView()
        case .requiresApproval:
            Button("Approve Helper…") { vm.openSystemSettings() }
                .buttonStyle(.bordered).tint(.orange)
        default:
            Button("Set Up Helper…") { vm.retryInstall() }
                .buttonStyle(.bordered).tint(.red)
        }
    }
}

// MARK: - Config detail (editable)

private struct ConfigDetailView: View {
    @EnvironmentObject var vm: AppViewModel
    let configID: UUID

    var body: some View {
        if let config = vm.configs.first(where: { $0.id == configID }) {
            VStack(spacing: 0) {
                HostsEditorView(text: Binding(
                    get: { vm.configs.first(where: { $0.id == configID })?.content ?? "" },
                    set: { vm.updateConfigContent(configID, content: $0) }
                ))
                Divider()
                HStack(spacing: 12) {
                    Spacer()
                    let lines = config.content.components(separatedBy: "\n").count
                    Text("\(lines) lines")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    let size = config.content.utf8.count
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .navigationTitle(config.name)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    helperButton
                }
            }
        } else {
            ContentUnavailableView("Config not found", systemImage: "questionmark")
        }
    }

    @ViewBuilder
    private var helperButton: some View {
        switch vm.helperStatus {
        case .enabled:
            EmptyView()
        case .requiresApproval:
            Button("Approve Helper…") { vm.openSystemSettings() }
                .buttonStyle(.bordered).tint(.orange)
        default:
            Button("Set Up Helper…") { vm.retryInstall() }
                .buttonStyle(.bordered).tint(.red)
        }
    }
}
