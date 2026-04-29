import SwiftUI

struct AddGroupSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var isPresented: Bool
    @State private var groupName = ""
    @State private var selectedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 16) {
            Text("New Group").font(.headline)

            TextField("Group Name", text: $groupName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            if vm.configs.isEmpty {
                Text("No items available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Select Items")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    List {
                        ForEach(vm.configs) { config in
                            Toggle(config.name, isOn: Binding(
                                get: { selectedIDs.contains(config.id) },
                                set: { isOn in
                                    if isOn { selectedIDs.insert(config.id) }
                                    else { selectedIDs.remove(config.id) }
                                }
                            ))
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 280, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { commitAdd() }
                    .buttonStyle(.borderedProminent)
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func commitAdd() {
        let name = groupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let ordered = vm.configs.map(\.id).filter { selectedIDs.contains($0) }
        vm.addGroup(name: name, memberIDs: ordered)
        isPresented = false
    }
}
