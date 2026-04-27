import SwiftUI

struct EditorRootView: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        Text("Hosts Editor")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
