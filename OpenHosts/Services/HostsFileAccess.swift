#if APPSTORE
import Foundation

/// Read-only sandboxed access to `/private/etc/hosts` for the Mac App Store build.
///
/// This version can save a security-scoped bookmark and read the file. It does
/// not write hosts. The bookmark must come from an `NSOpenPanel` selection.
/// `AppStoreOnboarding` calls `grantHostsFileAccess(to:)` with that URL.
enum HostsFileAccess {
    /// Canonical path. `/etc/hosts` is a symlink to this file.
    static let hostsPath = "/private/etc/hosts"

    /// `/etc` is a symlink to `/private/etc`. A sandboxed app may be unable to
    /// resolve that link, so either path is the hosts file.
    private static let hostsPaths: Set<String> = ["/etc/hosts", hostsPath]

    private static let bookmarkDefaultsKey = "hostsFileSecurityScopedBookmark"

    /// Read scope only. A read-write scope is not created in this version.
    private static let readBookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope,
        .securityScopeAllowOnlyReadAccess,
    ]

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil
    }

    /// True when a stored bookmark still resolves to `/etc/hosts` or
    /// `/private/etc/hosts`. This does not check write access.
    static func hasValidBookmark() -> Bool {
        guard hasBookmark else { return false }
        guard let url = try? resolveBookmark() else { return false }
        return isHostsFile(url)
    }

    /// True when `url` is the hosts file, before or after symlink resolution.
    ///
    /// `standardizedFileURL` and `resolvingSymlinksInPath` can both leave
    /// `/etc/hosts` unchanged inside the sandbox. That path is still the file.
    static func isHostsFile(_ url: URL) -> Bool {
        if hostsPaths.contains(url.standardizedFileURL.path) {
            return true
        }
        return hostsPaths.contains(canonicalHostsURL(url).path)
    }

    /// Saves a read-only security-scoped bookmark for the user-selected hosts file.
    ///
    /// The bookmark is created from `userSelectedURL` itself so the security scope
    /// stays attached. `/etc/hosts` and `/private/etc/hosts` are both accepted.
    static func grantHostsFileAccess(to userSelectedURL: URL) throws {
        guard userSelectedURL.startAccessingSecurityScopedResource() else {
            throw HostsFileAccessError.accessDenied
        }
        defer { userSelectedURL.stopAccessingSecurityScopedResource() }
        try storeBookmark(for: userSelectedURL)
    }

    private static func storeBookmark(for userSelectedURL: URL) throws {
        guard isHostsFile(userSelectedURL) else {
            throw HostsFileAccessError.wrongFile(selectedPath: canonicalHostsURL(userSelectedURL).path)
        }
        let data: Data
        do {
            data = try userSelectedURL.bookmarkData(
                options: readBookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw HostsFileAccessError.bookmarkFailed(error.localizedDescription)
        }
        UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
    }

    static func read() throws -> String {
        try withHostsFile { url in
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw HostsFileAccessError.readFailed(error.localizedDescription)
            }
        }
    }

    /// This App Store version does not write the hosts file.
    static func write(_ content: String) throws {
        _ = content
        throw HostsFileAccessError.notWritable
    }

    private static func withHostsFile<T>(_ body: (URL) throws -> T) throws -> T {
        let resolved = try resolveBookmark()
        guard resolved.startAccessingSecurityScopedResource() else {
            throw HostsFileAccessError.accessDenied
        }
        defer { resolved.stopAccessingSecurityScopedResource() }
        guard isHostsFile(resolved) else {
            throw HostsFileAccessError.wrongFile(selectedPath: canonicalHostsURL(resolved).path)
        }
        // Open the bookmarked URL. Rewriting it to the symlink target drops the
        // security scope, and the sandbox may not resolve `/etc/hosts` anyway.
        return try body(resolved)
    }

    private static func resolveBookmark() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDefaultsKey) else {
            throw HostsFileAccessError.noBookmark
        }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw HostsFileAccessError.bookmarkStale
        }
        if isStale {
            guard url.startAccessingSecurityScopedResource() else {
                throw HostsFileAccessError.bookmarkStale
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let refreshed = try url.bookmarkData(
                    options: readBookmarkOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: bookmarkDefaultsKey)
            } catch {
                throw HostsFileAccessError.bookmarkStale
            }
        }
        return url
    }

    private static func canonicalHostsURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}

enum HostsFileAccessError: LocalizedError {
    case noBookmark
    case bookmarkStale
    case bookmarkFailed(String)
    case wrongFile(selectedPath: String)
    case accessDenied
    case notWritable
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBookmark:
            return "No access to /private/etc/hosts yet. Choose the hosts file to grant access."
        case .bookmarkStale:
            return "Saved access to /private/etc/hosts is out of date. Choose the hosts file again."
        case .bookmarkFailed(let detail):
            return "Could not save access to /private/etc/hosts: \(detail)"
        case .wrongFile(let selectedPath):
            return "Select /etc/hosts (the resolved path must be /private/etc/hosts). Selected: \(selectedPath)"
        case .accessDenied:
            return "macOS denied security-scoped access to /private/etc/hosts."
        case .notWritable:
            return "This App Store version cannot write /private/etc/hosts. Read access can be saved; writing the hosts file is not part of this version."
        case .readFailed(let detail):
            return "Could not read /private/etc/hosts: \(detail)"
        }
    }
}
#endif
