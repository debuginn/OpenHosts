import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 300)
        .onAppear { vm.refreshHelperStatus() }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.setLaunchAtLogin($0) }
                ))
                Toggle("Show in Dock", isOn: Binding(
                    get: { vm.showInDock },
                    set: {
                        vm.showInDock = $0
                        if $0 {
                            DockManager.showDock()
                            NSApp.activate(ignoringOtherApps: true)
                        } else {
                            let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
                            DockManager.hideDock()
                            for w in visibleWindows { w.makeKeyAndOrderFront(nil) }
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                ))
            }

            Section("Privileged Helper") {
                HStack {
                    Text("Status")
                    Spacer()
                    helperStatusLabel
                }

                switch vm.helperStatus {
                case .enabled:
                    EmptyView()
                case .requiresApproval:
                    Button("Open System Settings") { vm.openSystemSettings() }
                default:
                    Button("Install Helper") { vm.retryInstall() }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("OpenHosts")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\u{00A9} 2026 debuginn")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 20) {
                Link(destination: URL(string: "https://github.com/debuginn/OpenHosts")!) {
                    Label("GitHub", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/debuginn/OpenHosts/issues/new")!) {
                    Label("Report Issue", systemImage: "exclamationmark.bubble")
                }
                Link(destination: URL(string: "https://github.com/debuginn/OpenHosts/releases")!) {
                    Label("Releases", systemImage: "arrow.down.circle")
                }
            }
            .font(.callout)

            Text("License: MIT")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Helpers

    @ViewBuilder
    private var helperStatusLabel: some View {
        switch vm.helperStatus {
        case .enabled:
            Label("Enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .requiresApproval:
            Label("Requires Approval", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        default:
            Label("Not Installed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
}
