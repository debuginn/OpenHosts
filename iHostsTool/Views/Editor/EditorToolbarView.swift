import SwiftUI

struct EditorToolbarView: View {
    @EnvironmentObject var vm: AppViewModel
    var onSave: () -> Void
    var onApply: () -> Void

    var body: some View {
        HStack {
            Button("Save", action: onSave)
                .keyboardShortcut("s")
                .buttonStyle(.bordered)

            Button(action: onApply) {
                HStack(spacing: 4) {
                    if vm.isApplyingHosts { ProgressView().controlSize(.mini) }
                    Text("Apply to System")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isApplyingHosts)
        }
    }
}
