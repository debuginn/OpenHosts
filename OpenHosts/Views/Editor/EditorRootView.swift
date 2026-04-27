import SwiftUI
import SharedKit

struct EditorRootView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selection: SidebarItem? = nil
    @State private var editorVMs: [UUID: EditorViewModel] = [:]

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            if let selection {
                editorContent(for: selection)
            } else {
                ContentUnavailableView(
                    "Select a Module or Profile",
                    systemImage: "doc.text",
                    description: Text("Choose an item from the sidebar to edit.")
                )
            }
        }
        .toolbar {
            if selection != nil {
                ToolbarItem(placement: .automatic) {
                    EditorToolbarView(
                        onSave: { saveSelection() },
                        onApply: { Task { await vm.applyHosts() } }
                    )
                }
            }
        }
        .navigationTitle("Hosts Editor")
    }

    @ViewBuilder
    private func editorContent(for item: SidebarItem) -> some View {
        switch item {
        case .module(let id):
            if let idx = vm.state.modules.firstIndex(where: { $0.id == id }) {
                editorView(for: vm.state.modules[idx], key: id)
            }
        case .profile(let id):
            if let profile = vm.state.profiles.first(where: { $0.id == id }),
               let group = profile.groups.first {
                editorView(for: group, key: id)
            } else {
                Text("This profile has no groups yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func editorView(for group: HostsGroup, key: UUID) -> some View {
        let evm = editorVMs[key] ?? EditorViewModel(group: group)
        return HostsEditorView(
            text: Binding(
                get: { evm.content },
                set: { evm.content = $0; evm.markDirty() }
            ),
            onChange: { evm.markDirty() }
        )
        .onAppear { editorVMs[key] = evm }
    }

    private func saveSelection() {
        guard let selection else { return }
        switch selection {
        case .module(let id):
            guard let idx = vm.state.modules.firstIndex(where: { $0.id == id }),
                  let evm = editorVMs[id] else { return }
            evm.save(to: &vm.state.modules[idx])
            vm.updateModule(vm.state.modules[idx])
        case .profile(let id):
            guard let pidx = vm.state.profiles.firstIndex(where: { $0.id == id }),
                  let group = vm.state.profiles[pidx].groups.first,
                  let evm = editorVMs[group.id] else { return }
            var g = group
            evm.save(to: &g)
            vm.state.profiles[pidx].groups[0] = g
            vm.updateProfile(vm.state.profiles[pidx])
        }
    }
}
