import Foundation
import ServiceManagement

enum HelperInstaller {
    private static let plistName = "com.debuginn.OpenHosts.Helper.plist"

    static var status: SMAppService.Status {
        SMAppService.daemon(plistName: plistName).status
    }

    static var isInstalled: Bool {
        status == .enabled
    }

    // Registers the daemon. Throws if registration fails outright.
    // Returns true if enabled immediately, false if pending user approval.
    @discardableResult
    static func installIfNeeded() throws -> Bool {
        let service = SMAppService.daemon(plistName: plistName)
        switch service.status {
        case .enabled:
            return true
        case .requiresApproval:
            // Already registered but user hasn't approved yet in System Settings.
            // Re-calling register() opens System Settings → Login Items.
            try service.register()
            return false
        case .notRegistered, .notFound:
            try service.register()
            return service.status == .enabled
        @unknown default:
            try service.register()
            return service.status == .enabled
        }
    }

    static func uninstall() throws {
        try SMAppService.daemon(plistName: plistName).unregister()
    }
}
