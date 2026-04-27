import SwiftUI

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
                    Text(vm.isApplyingHosts ? "Applying…" : "Apply to System")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isApplyingHosts)

            if let err = vm.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal)
    }
}
