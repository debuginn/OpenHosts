import SwiftUI
import SharedKit

struct ModuleListView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.state.modules) { module in
                    ModuleRowView(module: module)
                }
                .onDelete { offsets in
                    offsets.map { vm.state.modules[$0].id }.forEach(vm.deleteModule)
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 80, maxHeight: 200)

            Button(action: { vm.addModule(name: "New Module") }) {
                Label("Add Module", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

struct ModuleRowView: View {
    let module: HostsGroup
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        let name = module.name
        Toggle(isOn: Binding(
            get: { module.isEnabled },
            set: { _ in vm.toggleModule(module.id) }
        )) {
            Text(name).font(.body)
        }
        .toggleStyle(.switch)
    }
}
