import SwiftUI
import SharedKit

enum SidebarItem: Hashable {
    case module(UUID)
    case profile(UUID)
}

struct SidebarView: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Modules") {
                ForEach(vm.state.modules) { mod in
                    Label(mod.name, systemImage: "square.stack")
                        .tag(SidebarItem.module(mod.id))
                }
                .onDelete { offsets in
                    offsets.map { vm.state.modules[$0].id }.forEach(vm.deleteModule)
                }
            }
            Section("Profiles") {
                ForEach(vm.state.profiles) { profile in
                    Label(profile.name, systemImage: "person.crop.rectangle.stack")
                        .tag(SidebarItem.profile(profile.id))
                }
                .onDelete { offsets in
                    offsets.map { vm.state.profiles[$0].id }.forEach(vm.deleteProfile)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Add Module") { vm.addModule(name: "New Module") }
                    Button("Add Profile") { vm.addProfile(name: "New Profile") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
