import SwiftUI
import SharedKit

@main
struct OpenHostsApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(vm)
        } label: {
            Label("OpenHosts", systemImage: "network.badge.shield.half.filled")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Window("Hosts Editor", id: "editor") {
            EditorRootView()
                .environmentObject(vm)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
