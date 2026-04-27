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
        connection.exportedInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        connection.exportedObject = HostsHelperImpl()
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "com.debuginn.iHosts.Helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
