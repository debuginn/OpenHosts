import Foundation
import SharedKit

final class HelperXPCClient: @unchecked Sendable {
    private var connection: NSXPCConnection?

    private func makeConnection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: "com.debuginn.iHosts.Helper",
                                options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: HostsHelperProtocol.self)
        c.invalidationHandler = { [weak self] in self?.connection = nil }
        c.resume()
        return c
    }

    private func proxy() -> any HostsHelperProtocol {
        if connection == nil { connection = makeConnection() }
        return connection!.remoteObjectProxyWithErrorHandler { [weak self] _ in
            self?.connection = nil
        } as! any HostsHelperProtocol
    }

    func writeHosts(_ content: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            proxy().writeHosts(content) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func readHosts() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            proxy().readHosts { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: content ?? "")
                }
            }
        }
    }
}
