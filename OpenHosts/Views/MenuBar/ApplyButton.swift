import SwiftUI
import ServiceManagement

struct ApplyButton: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 4) {
            Button {
                Task { await vm.applyHosts() }
            } label: {
                HStack {
                    if vm.isApplyingHosts {
                        ProgressView().controlSize(.small)
                    }
                    Text(buttonLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isApplyingHosts || vm.helperStatus != .enabled)

            if vm.helperStatus == .requiresApproval {
                Text("Waiting for approval in System Settings → Login Items")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else if vm.helperStatus != .enabled {
                Text("Helper not authorized — restart app to retry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let err = vm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }

    private var buttonLabel: String {
        if vm.isApplyingHosts { return "Applying…" }
        if vm.helperStatus == .requiresApproval { return "Awaiting Approval…" }
        if vm.helperStatus != .enabled { return "Helper Not Ready" }
        return "Apply to System"
    }
}
