import Foundation
import ServiceManagement

enum HelperInstaller {
    private static let plistName = "com.debuginn.iHosts.Helper.plist"

    static var isInstalled: Bool {
        SMAppService.daemon(plistName: plistName).status == .enabled
    }

    static func installIfNeeded() throws {
        let service = SMAppService.daemon(plistName: plistName)
        guard service.status != .enabled else { return }
        try service.register()
    }

    static func uninstall() throws {
        try SMAppService.daemon(plistName: plistName).unregister()
    }
}
