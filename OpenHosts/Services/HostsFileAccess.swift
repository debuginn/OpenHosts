#if APPSTORE
import Foundation
import Darwin

/// Sandboxed access to `/private/etc/hosts` for the Mac App Store build.
///
/// The bookmark must come from an `NSOpenPanel` selection. Creating a URL in
/// code is not a user-selected file, and bookmark creation will fail.
///
/// TODO(UI): Onboarding should present the open panel for `/etc/hosts` and call
/// `storeBookmark(for:)`. There is no onboarding UI in this change.
enum HostsFileAccess {
    /// Canonical path. `/etc/hosts` is a symlink to this file; bookmarks use the real path.
    static let hostsPath = "/private/etc/hosts"

    private static let bookmarkDefaultsKey = "hostsFileSecurityScopedBookmark"

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkDefaultsKey) != nil
    }

    /// Saves an app-scoped security-scoped bookmark for `/private/etc/hosts`.
    ///
    /// TODO(UI): Call from the App Store onboarding screen with the URL returned
    /// by `NSOpenPanel`. Do not build the URL yourself.
    static func storeBookmark(for userSelectedURL: URL) throws {
        let url = canonicalHostsURL(userSelectedURL)
        guard url.path == hostsPath else {
            throw HostsFileAccessError.wrongFile(selectedPath: url.path)
        }
        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope],
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

    /// Overwrites the existing file's bytes. This is not an atomic replace:
    /// renaming a new inode would drop the ACLs on `/private/etc/hosts`.
    static func write(_ content: String) throws {
        try withHostsFile { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HostsFileAccessError.notWritable
            }
            guard FileManager.default.isWritableFile(atPath: url.path) else {
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

    private static func withHostsFile<T>(_ body: (URL) throws -> T) throws -> T {
        let resolved = try resolveBookmark()
        guard resolved.startAccessingSecurityScopedResource() else {
            throw HostsFileAccessError.accessDenied
        }
        defer { resolved.stopAccessingSecurityScopedResource() }
        let url = canonicalHostsURL(resolved)
        guard url.path == hostsPath else {
            throw HostsFileAccessError.wrongFile(selectedPath: url.path)
        }
        return try body(url)
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
                    options: [.withSecurityScope],
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
