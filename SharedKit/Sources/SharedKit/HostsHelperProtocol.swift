import Foundation

@objc public protocol HostsHelperProtocol {
    func writeHosts(_ content: String, reply: @escaping (Error?) -> Void)
    func readHosts(reply: @escaping (String?, Error?) -> Void)
}
