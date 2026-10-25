#if APPSTORE
import Foundation
import Darwin

/// Sandboxed access to `/private/etc/hosts` for the Mac App Store build.
///
/// The bookmark must come from an `NSOpenPanel` selection. Creating a URL in
/// code is not a user-selected file, and bookmark creation will fail.
/// `AppStoreOnboarding` calls `grantHostsFileAccess(to:)` with that URL.
enum HostsFileAccess {
    /// Canonical path. `/etc/hosts` is a symlink to this file.
    static let hostsPath = "/private/etc/hosts"

    /// `/etc` is a symlink to `/private/etc`. A sandboxed app may be unable to
    /// resolve that link, so either path is the hosts file.
    private static let hostsPaths: Set<String> = ["/etc/hosts", hostsPath]

    private static let bookmarkDefaultsKey = "hostsFileSecurityScopedBookmark"

    /// Read-write security scope. This is what later `open(O_WRONLY)` needs.
    /// Creating it asks the sandbox for write access, which fails until the
    /// user-selected file is writable.
    private static let readWriteBookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope,
    ]

    /// Used only when a read-write scope cannot be created yet. Enough to
    /// remember the selected hosts file; not enough to write it later.
    private static let readOnlyBookmarkOptions: URL.BookmarkCreationOptions = [
        .withSecurityScope,
        .securityScopeAllowOnlyReadAccess,
    ]

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil
    }

    /// True when a stored bookmark still resolves to `/etc/hosts` or
    /// `/private/etc/hosts`. This does not check whether the file is writable.
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

    /// Saves an app-scoped security-scoped bookmark for the user-selected hosts file.
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

    /// Opens `/private/etc/hosts` for writing and closes it without changing bytes.
    static func probeWriteAccess() throws {
        try withHostsFile(forWriting: true) { url in
            try requireWrite(url)
        }
    }

    private static func storeBookmark(for userSelectedURL: URL) throws {
        guard isHostsFile(userSelectedURL) else {
            throw HostsFileAccessError.wrongFile(selectedPath: canonicalHostsURL(userSelectedURL).path)
        }
        let data: Data
        do {
            data = try persistedBookmarkData(for: userSelectedURL)
        } catch {
            throw HostsFileAccessError.bookmarkFailed(error.localizedDescription)
        }
        UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
    }

    /// Read-write scope when the sandbox allows it, otherwise read-only.
    ///
    /// The read-only fallback is what lets selection succeed before the write
    /// ACL exists. A read-write bookmark is what makes `probeWriteAccess` succeed
    /// after that ACL is granted.
    private static func persistedBookmarkData(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: readWriteBookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: readOnlyBookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
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

    /// Overwrites the existing file's bytes. This is not an atomic replace:
    /// renaming a new inode would drop the ACLs on `/private/etc/hosts`.
    static func write(_ content: String) throws {
        try withHostsFile(forWriting: true) { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HostsFileAccessError.notWritable
            }
            let data = Data(content.utf8)
            let handle: FileHandle
            do {
                handle = try FileHandle(forWritingTo: url)
            } catch {
                throw mappedWriteError(error)
            }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: data)
                try handle.truncate(atOffset: UInt64(data.count))
            } catch {
                throw mappedWriteError(error)
            }
        }
    }

    private static func withHostsFile<T>(forWriting: Bool = false, _ body: (URL) throws -> T) throws -> T {
        let resolved = try resolveBookmark()
        guard resolved.startAccessingSecurityScopedResource() else {
            throw HostsFileAccessError.accessDenied
        }
        var promoted: URL?
        defer {
            promoted?.stopAccessingSecurityScopedResource()
            resolved.stopAccessingSecurityScopedResource()
        }
        guard isHostsFile(resolved) else {
            throw HostsFileAccessError.wrongFile(selectedPath: canonicalHostsURL(resolved).path)
        }
        // A bookmark saved before the write ACL exists is read-only. Once the
        // ACL is present, replace it and write through that read-write scope.
        let url: URL
        if forWriting, let upgraded = upgradedReadWriteURL(from: resolved) {
            promoted = upgraded
            url = upgraded
        } else {
            url = resolved
        }
        return try body(url)
    }

    /// Bookmark source, then the symlink-resolved URL when it is a different hosts path.
    /// The resolved URL is only a candidate; it is kept only if a write open succeeds.
    private static func readWriteCandidates(for url: URL) -> [URL] {
        var urls = [url]
        let resolved = canonicalHostsURL(url)
        if resolved.path != url.standardizedFileURL.path {
            urls.append(resolved)
        }
        return urls
    }

    /// A read-write replacement when `url` itself cannot be opened for write.
    /// Nil leaves the caller on `url`. The stored bookmark changes only after a
    /// write open on the replacement succeeds.
    private static func upgradedReadWriteURL(from url: URL) -> URL? {
        if canOpenForWrite(url) {
            return nil
        }
        for candidate in readWriteCandidates(for: url) {
            guard let data = try? candidate.bookmarkData(
                options: readWriteBookmarkOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { continue }
            var isStale = false
            guard let promoted = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isHostsFile(promoted),
               promoted.startAccessingSecurityScopedResource() else { continue }
            guard canOpenForWrite(promoted) else {
                promoted.stopAccessingSecurityScopedResource()
                continue
            }
            UserDefaults.standard.set(data, forKey: bookmarkDefaultsKey)
            return promoted
        }
        return nil
    }

    private static func requireWrite(_ url: URL) throws {
        if canOpenForWrite(url) { return }
        let code = errno
        if code == EACCES || code == EPERM {
            throw HostsFileAccessError.notWritable
        }
        throw HostsFileAccessError.writeFailed(String(cString: strerror(code)))
    }

    /// Opens for write and closes immediately. On failure `errno` is left set by `open`.
    private static func canOpenForWrite(_ url: URL) -> Bool {
        let fd = open(url.path, O_WRONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
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
                let refreshed = try persistedBookmarkData(for: url)
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

    private static func mappedWriteError(_ error: Error) -> HostsFileAccessError {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM)) {
            return .notWritable
        }
        // NSFileWriteNoPermissionError
        if ns.domain == NSCocoaErrorDomain && ns.code == 513 {
            return .notWritable
        }
        return .writeFailed(error.localizedDescription)
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
    case writeFailed(String)

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
            return "/private/etc/hosts is not writable. Access was granted, but the file permissions still block writes."
        case .readFailed(let detail):
            return "Could not read /private/etc/hosts: \(detail)"
        case .writeFailed(let detail):
            return "Could not write /private/etc/hosts: \(detail)"
        }
    }
}
#endif
