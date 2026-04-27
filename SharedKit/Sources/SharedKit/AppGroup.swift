import Foundation

public enum AppGroup {
    public static let identifier = "group.com.debuginn.iHosts"

    public static var containerURL: URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(identifier)
    }

    public static var stateFileURL: URL {
        containerURL.appending(path: "state.json")
    }

    public static let darwinNotificationName = "com.debuginn.iHosts.stateChanged"
}
