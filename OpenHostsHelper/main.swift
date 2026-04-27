import Foundation
import SharedKit

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
        guard isCallerAuthorized(pid: connection.processIdentifier) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        connection.exportedObject = HostsHelperImpl()
        connection.resume()
        return true
    }

    private func isCallerAuthorized(pid: pid_t) -> Bool {
        guard let callerPath = executablePath(for: pid) else { return false }
        return callerPath.contains("OpenHosts.app")
    }

    private func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0
            ? String(cString: buffer) : nil
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "com.debuginn.OpenHosts.Helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
