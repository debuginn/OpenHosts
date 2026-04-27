import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject var vm: AppViewModel
    var body: some View {
        Text("iHosts Menu Bar")
            .frame(width: 280, height: 200)
    }
}
