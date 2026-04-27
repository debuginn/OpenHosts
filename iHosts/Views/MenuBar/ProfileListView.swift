import SwiftUI
import SharedKit

struct ProfileListView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(vm.state.profiles) { profile in
                ProfileRowView(profile: profile)
            }
            .listStyle(.sidebar)
            .frame(minHeight: 80, maxHeight: 200)

            Button(action: { vm.addProfile(name: "New Profile") }) {
                Label("Add Profile", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}

struct ProfileRowView: View {
    let profile: Profile
    @EnvironmentObject var vm: AppViewModel

    private var isActive: Bool { vm.state.activeProfileId == profile.id }

    var body: some View {
        Button {
            vm.activateProfile(isActive ? nil : profile.id)
        } label: {
            HStack {
                Text(profile.name).font(.body)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
