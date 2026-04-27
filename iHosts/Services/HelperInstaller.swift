import Foundation
import ServiceManagement

enum HelperInstaller {
    static var isInstalled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func installIfNeeded() throws {
        guard !isInstalled else { return }
        try SMAppService.mainApp.register()
    }

    static func uninstall() throws {
        try SMAppService.mainApp.unregister()
    }
}
