import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.setLaunchAtLogin($0) }
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

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 280)
        .onAppear { vm.refreshHelperStatus() }
    }

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
