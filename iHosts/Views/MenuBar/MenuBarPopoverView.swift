import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.openWindow) private var openWindow

    private var isProfileMode: Bool { vm.state.activeProfileId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("iHosts")
                    .font(.title3.bold())
                Spacer()
                Button {
                    openWindow(id: "editor")
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Open Editor")
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            ModeToggleView()

            if isProfileMode {
                ProfileListView()
            } else {
                ModuleListView()
            }

            Divider()

            ApplyButton()
                .padding(.bottom, 12)
        }
        .frame(width: 280)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
