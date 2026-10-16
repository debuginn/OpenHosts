import Foundation

/// Code-signing requirement for processes allowed to talk to the privileged helper.
///
/// `scripts/verify-helper-auth.sh` parses `requirement` and evaluates it with
/// `codesign --test-requirement`. Keep the two in sync.
private enum CallerAuthorization {
    /// Team TXVGDTDY84, bundle identifier com.debuginn.OpenHosts.
    /// Matches Developer ID and Apple Development signatures for that team.
    /// A path that merely contains "OpenHosts.app" does not satisfy this.
    static let requirement = "anchor apple generic and identifier \"com.debuginn.OpenHosts\" and certificate leaf[subject.OU] = \"TXVGDTDY84\""
}

@objc protocol HostsHelperProtocol {
    func writeHosts(_ content: String, reply: @escaping (Error?) -> Void)
    func readHosts(reply: @escaping (String?, Error?) -> Void)
}

final class HostsHelperImpl: NSObject, HostsHelperProtocol {
    func writeHosts(_ content: String, reply: @escaping (Error?) -> Void) {
        do {
            try content.write(toFile: "/etc/hosts", atomically: true, encoding: .utf8)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func readHosts(reply: @escaping (String?, Error?) -> Void) {
        do {
            let content = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
            reply(content, nil)
        } catch {
            reply(nil, error)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // macOS 13+: XPC checks this requirement against the peer's audit token
        // before delivering messages. Call it once, before resume(). A renamed
        // or copied binary whose path contains "OpenHosts.app" is rejected
        // unless it is signed with the team and bundle id above.
        connection.setCodeSigningRequirement(CallerAuthorization.requirement)
        connection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        connection.exportedObject = HostsHelperImpl()
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "com.debuginn.OpenHosts.Helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
