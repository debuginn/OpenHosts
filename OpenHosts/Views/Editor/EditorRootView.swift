import SwiftUI

struct EditorRootView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detailContent
        }
        .onAppear {
            vm.loadAll()
            #if APPSTORE
            AppStoreOnboarding.shared.startIfNeeded()
            #endif
        }
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
            #if APPSTORE
            if vm.hasValidHostsBookmark {
                hostsEditor
            } else {
                ContentUnavailableView {
                    Text("需要授权才能编辑 hosts")
                } description: {
                    EmptyView()
                } actions: {
                    Button("授权…") { vm.beginAppStoreOnboarding() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            hostsEditor
            #endif
            Divider()
            HStack(spacing: 12) {
                #if APPSTORE
                if vm.hostsWritePermitted {
                    Spacer()
                    hostsFileStats
                } else {
                    readOnlyBadge
                    Spacer()
                }
                #else
                readOnlyBadge
                Spacer()
                hostsFileStats
                #endif
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .navigationTitle("/etc/hosts")
        .toolbar {
            #if APPSTORE
            if !vm.hostsWritePermitted {
                ToolbarItem(placement: .primaryAction) {
                    Text("⚠ 未授权")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("授权…") { vm.beginAppStoreOnboarding() }
                }
                ToolbarItem(placement: .automatic) {
                    historyButton
                }
            } else {
                // The History icon is .automatic above. Once the pinned primary
                // actions are gone, that placement is what macOS puts in the overflow.
                ToolbarItem(placement: .primaryAction) {
                    historyButton
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                historyButton
            }
            ToolbarItem(placement: .automatic) {
                helperButton
            }
            #endif
        }
        .inspector(isPresented: $showingHistory) {
            HistoryInspectorView()
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
    }

    private var historyButton: some View {
        Button { withAnimation { showingHistory.toggle() } } label: {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
        }
        .help("History")
    }

    private var readOnlyBadge: some View {
        Text("Read Only")
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            .foregroundStyle(.secondary)
    }

    private var hostsEditor: some View {
        HostsEditorView(
            text: Binding(get: { vm.systemHostsContent }, set: { _ in }),
            isEditable: false
        )
    }

    private var hostsFileStats: some View {
        let lines = vm.systemHostsContent.components(separatedBy: "\n").count
        let size = vm.systemHostsContent.utf8.count
        return HStack(spacing: 12) {
            Text("\(lines) lines")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    #if !APPSTORE
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
    #endif
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
                #if !APPSTORE
                ToolbarItem(placement: .automatic) {
                    helperButton
                }
                #endif
            }
        } else {
            ContentUnavailableView("Config not found", systemImage: "questionmark")
        }
    }

    #if !APPSTORE
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
    #endif
}
