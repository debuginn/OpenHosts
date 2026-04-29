import Foundation
import ServiceManagement
import OSLog
import AppKit

enum HelperInstaller {
    private static let plistName = "com.debuginn.OpenHosts.Helper.plist"
    private static let log = Logger(subsystem: "com.debuginn.OpenHosts", category: "HelperInstaller")

    static var status: SMAppService.Status {
        let s = SMAppService.daemon(plistName: plistName).status
        log.debug("status query → \(s.debugDescription)")
        return s
    }

    static var isInstalled: Bool { status == .enabled }

    // Attempts first-time registration. No-op if already registered or enabled.
    static func registerIfNeeded() throws {
        let service = SMAppService.daemon(plistName: plistName)
        let current = service.status
        log.info("registerIfNeeded called, status=\(current.debugDescription), bundle=\(Bundle.main.bundlePath)")

        switch current {
        case .enabled:
            log.info("already enabled, nothing to do")
        case .requiresApproval:
            log.info("already registered, pending user approval — call openSystemSettings()")
        case .notRegistered, .notFound:
            log.info("calling register()…")
            do {
                try service.register()
                log.info("register() succeeded, new status=\(service.status.debugDescription)")
            } catch {
                let ns = error as NSError
                if ns.domain == "SMAppServiceErrorDomain" && ns.code == 10 {
                    // alreadyRegistered — service exists, just query status below
                    log.info("register() → alreadyRegistered, treating as no-op")
                } else {
                    log.error("register() threw: \(ns)")
                    throw error
                }
            }
        @unknown default:
            log.warning("unknown status \(current.debugDescription), attempting register()")
            try service.register()
        }
    }

    static func openSystemSettings() {
        log.info("openSystemSettings called")
        SMAppService.openSystemSettingsLoginItems()

        // Fallback: open via NSWorkspace URL in case the SM API is silent on this OS version.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            log.info("openSystemSettings fallback URL: \(url)")
            NSWorkspace.shared.open(url)
        }
    }

    static func uninstall() throws {
        log.info("uninstalling helper")
        try SMAppService.daemon(plistName: plistName).unregister()
    }
}

private extension SMAppService.Status {
    var debugDescription: String {
        switch self {
        case .notRegistered:   return "notRegistered"
        case .enabled:         return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notFound:        return "notFound"
        @unknown default:      return "unknown(\(rawValue))"
        }
    }
}
