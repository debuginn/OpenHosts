import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var showingAddItemSheet = false
    @State private var showingAddGroupSheet = false
    @State private var newConfigName = ""
    @State private var renamingItemID: UUID?
    @State private var renamingGroupID: UUID?
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                sidebarRow(
                    selected: vm.selectedItem == .systemHosts,
                    action: { vm.selectedItem = .systemHosts }
                ) {
                    Label("/etc/hosts", systemImage: "doc.text.fill")
                }

                sectionHeader("My Hosts")

                ForEach(vm.configs) { config in
                    let item = AppViewModel.SidebarItem.config(config.id)
                    sidebarRow(
                        selected: vm.selectedItem == item,
                        action: { vm.selectedItem = item }
                    ) {
                        ConfigRowView(
                            config: config,
                            onToggle: { vm.toggleConfig(config.id) },
                            validationFailed: vm.validationFailedConfigID == config.id
                        )
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = config.name
                            renamingItemID = config.id
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            vm.deleteConfig(config.id)
                        }
                    }
                }

                ForEach(vm.groups) { group in
                    let item = AppViewModel.SidebarItem.group(group.id)
                    sidebarRow(
                        selected: vm.selectedItem == item,
                        action: { vm.selectedItem = item }
                    ) {
                        GroupRowView(
                            group: group,
                            onToggle: { vm.toggleGroup(group.id) }
                        )
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = group.name
                            renamingGroupID = group.id
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            vm.deleteGroup(group.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .navigationTitle("OpenHosts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Item") { showingAddItemSheet = true }
                    Button("New Group") { showingAddGroupSheet = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    openWindow(id: "settings")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                applyStatusView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showingAddItemSheet) {
            addItemSheet
        }
        .sheet(isPresented: $showingAddGroupSheet) {
            AddGroupSheet(isPresented: $showingAddGroupSheet)
        }
        .sheet(isPresented: Binding(
            get: { renamingItemID != nil },
            set: { if !$0 { renamingItemID = nil } }
        )) {
            VStack(spacing: 20) {
                Text("Rename Item")
                    .font(.headline)
                TextField("Title", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit { commitRenameItem() }
                HStack(spacing: 12) {
                    Button("Cancel") { renamingItemID = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("OK") { commitRenameItem() }
                        .buttonStyle(.borderedProminent)
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: Binding(
            get: { renamingGroupID != nil },
            set: { if !$0 { renamingGroupID = nil } }
        )) {
            VStack(spacing: 20) {
                Text("Rename Group")
                    .font(.headline)
                TextField("Title", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit { commitRenameGroup() }
                HStack(spacing: 12) {
                    Button("Cancel") { renamingGroupID = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("OK") { commitRenameGroup() }
                        .buttonStyle(.borderedProminent)
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Sidebar Row

    private func sidebarRow<Content: View>(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.gray.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { action() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Add Item Sheet

    private var addItemSheet: some View {
        VStack(spacing: 20) {
            Text("New Item")
                .font(.headline)
            TextField("Title", text: $newConfigName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { commitAddItem() }
            HStack(spacing: 12) {
                Button("Cancel") {
                    showingAddItemSheet = false
                    newConfigName = ""
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") { commitAddItem() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newConfigName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func commitRenameItem() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if let id = renamingItemID, !name.isEmpty {
            vm.renameConfig(id, to: name)
        }
        renamingItemID = nil
    }

    private func commitRenameGroup() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if let id = renamingGroupID, !name.isEmpty {
            vm.renameGroup(id, to: name)
        }
        renamingGroupID = nil
    }

    private func commitAddItem() {
        let name = newConfigName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        vm.addConfig(name: name)
        newConfigName = ""
        showingAddItemSheet = false
    }

    // MARK: - Status Footer

    @ViewBuilder
    private var applyStatusView: some View {
        switch vm.applyState {
        case .idle:
            helperStatusView
        case .applying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Applying…").font(.caption).foregroundStyle(.secondary)
            }
        case .success:
            Label("Applied", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var helperStatusView: some View {
        switch vm.helperStatus {
        case .enabled:
            EmptyView()
        case .requiresApproval:
            Button("Approve Helper…") { vm.openSystemSettings() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.orange)
        default:
            Button("Set Up Helper…") { vm.retryInstall() }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Config Row

struct ConfigRowView: View {
    let config: HostsConfig
    let onToggle: () -> Void
    var validationFailed: Bool = false

    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .frame(width: 20, height: 20)
                .foregroundStyle(config.isEnabled ? .blue : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                if validationFailed {
                    Text("Invalid hosts format")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if !config.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let count = config.content.components(separatedBy: "\n")
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        .count
                    Text("\(count) \(count == 1 ? "entry" : "entries")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(config.isEnabled ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .offset(x: shakeOffset)
        .onChange(of: validationFailed) {
            if validationFailed {
                withAnimation(.default.speed(4).repeatCount(3, autoreverses: true)) {
                    shakeOffset = 6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { shakeOffset = 0 }
                }
            }
        }
    }
}

// MARK: - Group Row

struct GroupRowView: View {
    let group: HostsGroupConfig
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder")
                .frame(width: 20, height: 20)
                .foregroundStyle(group.isEnabled ? .orange : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                Text("\(group.memberIDs.count) \(group.memberIDs.count == 1 ? "item" : "items")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(group.isEnabled ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(get: { group.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}
