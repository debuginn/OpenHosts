import Foundation

enum HostsValidator {

    static func validateContent(_ content: String) -> Bool {
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if !isValidHostsLine(parts) { return false }
        }
        return true
    }

    static func isValidHostsLine(_ parts: [Substring]) -> Bool {
        guard parts.count >= 2 else { return false }
        let ip = String(parts[0])
        guard isValidIP(ip) else { return false }
        for i in 1..<parts.count {
            let host = String(parts[i])
            if host.hasPrefix("#") { break }
            if !isValidHostname(host) { return false }
        }
        return true
    }

    static func isValidIP(_ str: String) -> Bool {
        var addr4 = in_addr()
        var addr6 = in6_addr()
        return inet_pton(AF_INET, str, &addr4) == 1
            || inet_pton(AF_INET6, str, &addr6) == 1
    }

    static func isValidHostname(_ str: String) -> Bool {
        if str.isEmpty || str.count > 253 { return false }
        let labels = str.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63
            && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            && !label.hasPrefix("-") && !label.hasSuffix("-")
        }
    }
}
