import Foundation
import SharedKit

final class HelperXPCClient: @unchecked Sendable {
    private var connection: NSXPCConnection?

    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: "com.debuginn.OpenHosts.Helper",
                                options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        c.invalidationHandler = { [weak self] in self?.connection = nil }
        c.resume()
        return c
    }

    func writeHosts(_ content: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            if connection == nil { connection = makeConnection() }
            let proxy = connection!.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.connection = nil
                continuation.resume(throwing: error)
            } as! any HostsHelperProtocol
            proxy.writeHosts(content) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func readHosts() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            if connection == nil { connection = makeConnection() }
            let proxy = connection!.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.connection = nil
                continuation.resume(throwing: error)
            } as! any HostsHelperProtocol
            proxy.readHosts { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: content ?? "")
                }
            }
        }
    }
}
