import SwiftUI

struct MenuBarMenuView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Button {
                dismissPopover()
                DockManager.showDock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [openWindow] in
                    openWindow(id: "editor")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .frame(width: 16)
                    Text("OpenHosts")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 8)

            VStack(spacing: 0) {
                ForEach(vm.configs) { config in
                    toggleRow(
                        icon: "doc.text",
                        name: config.name,
                        iconColor: .blue,
                        isOn: config.isEnabled,
                        action: { vm.toggleConfig(config.id) }
                    )
                }
                ForEach(vm.groups) { group in
                    toggleRow(
                        icon: "folder",
                        name: group.name,
                        iconColor: .orange,
                        isOn: group.isEnabled,
                        action: { vm.toggleGroup(group.id) }
                    )
                }
            }

            if vm.configs.isEmpty && vm.groups.isEmpty {
                Text("No items")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
            }

            Divider().padding(.horizontal, 8)

            Button {
                dismissPopover()
                DockManager.showDock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [openWindow] in
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                HStack {
                    Text("Settings")
                    Spacer()
                    Text("⌘,")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack {
                Text("Quit")
                Spacer()
                Text("⌘Q")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { NSApplication.shared.terminate(nil) }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 4)
        .frame(width: 200)
    }

    private func menuRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            dismissPopover()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(label)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func dismissPopover() {
        for window in NSApplication.shared.windows where window.isVisible {
            let name = String(describing: type(of: window))
            if name.contains("Panel") || name.contains("StatusItem") || name.contains("NSStatusBar") {
                window.orderOut(nil)
                return
            }
        }
        if let panel = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.level.rawValue > NSWindow.Level.normal.rawValue && $0.identifier?.rawValue != "editor"
        }) {
            panel.orderOut(nil)
        }
    }

    private func toggleRow(icon: String, name: String, iconColor: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isOn ? iconColor : .gray)
                .frame(width: 16)
            Text(name)
                .lineLimit(1)
                .foregroundStyle(isOn ? .primary : .secondary)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
