import SwiftUI

struct ModeToggleView: View {
    @EnvironmentObject var vm: AppViewModel

    private var isProfileMode: Bool { vm.state.activeProfileId != nil }

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { isProfileMode ? 1 : 0 },
            set: { newValue in
                if newValue == 0 {
                    vm.activateProfile(nil)
                } else if let first = vm.state.profiles.first {
                    vm.activateProfile(first.id)
                }
            }
        )) {
            Text("Modules").tag(0)
            Text("Profile").tag(1)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
