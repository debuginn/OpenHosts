import SwiftUI

@main
struct OpenHostsApp: App {
    @StateObject private var vm = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(vm)
                .onAppear {
                    DockManager.shared.setUpOnce()
                }
        } label: {
            Label("OpenHosts", systemImage: "apple.terminal")
        }
        .menuBarExtraStyle(.window)

        Window("Hosts Editor", id: "editor") {
            EditorRootView()
                .environmentObject(vm)
                .onReceive(NotificationCenter.default.publisher(for: .reopenEditorWindow)) { _ in
                    openWindow(id: "editor")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onOpenURL { url in
                    guard url.scheme == "openhosts" else { return }
                    DockManager.showDock()
                    openWindow(id: "editor")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    DockManager.showDock()
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About OpenHosts") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "OpenHosts",
                        .credits: NSAttributedString(
                            string: "A native macOS app for managing /etc/hosts\nhttps://github.com/debuginn/OpenHosts",
                            attributes: [.font: NSFont.systemFont(ofSize: 11)]
                        ),
                    ])
                }
            }
            CommandGroup(replacing: .help) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/debuginn/OpenHosts")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/debuginn/OpenHosts/issues/new")!)
                Divider()
                Link("Release Notes", destination: URL(string: "https://github.com/debuginn/OpenHosts/releases")!)
            }
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(vm)
        }
        .windowResizability(.contentSize)
    }
}

final class DockManager: NSObject, @unchecked Sendable {
    static let shared = DockManager()
    private var didSetUp = false

    func setUpOnce() {
        guard !didSetUp else { return }
        didSetUp = true
        NSApp.setActivationPolicy(.accessory)
        setUp()
    }

    private func setUp() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    static func showDock() {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        guard showInDock else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func hideDock() {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        guard let id = window.identifier?.rawValue,
              id.contains("editor") || id.contains("settings") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let hasAppWindow = NSApp.windows.contains {
                guard let wid = $0.identifier?.rawValue else { return false }
                return (wid.contains("editor") || wid.contains("settings")) && $0.isVisible
            }
            if !hasAppWindow {
                Self.hideDock()
            }
        }
    }
}

extension Notification.Name {
    static let reopenEditorWindow = Notification.Name("reopenEditorWindow")
}
