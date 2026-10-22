#if APPSTORE
import AppKit

/// First-launch write permission for the Mac App Store build.
///
/// System alerts and the open panel only. The Developer ID target does not compile this.
@MainActor
final class AppStoreOnboarding: NSObject, NSAlertDelegate {
    static let shared = AppStoreOnboarding()

    /// Literal shell text. `$(whoami)` is expanded by Terminal, not by the app.
    static let grantCommand = "sudo chmod +a \"user:$(whoami) allow write\" /private/etc/hosts"
    static let revokeCommand = "sudo chmod -a \"user:$(whoami) allow write\" /private/etc/hosts"
    static let flushCommand = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

    var onFinished: (@MainActor () -> Void)?

    private var isPresenting = false
    private var didAutoPresent = false
    private var didRequestEditor = false
    private var waitingForWindow = false
    private var authorizeRetries = 0
    private var retainedAlert: NSAlert?
    private var retainedPanel: NSOpenPanel?
    private var sheetHandler: (@MainActor (Int) -> Void)?

    private override init() {
        super.init()
    }

    /// Opens the editor once per launch when no bookmark resolves to the hosts file.
    func requestEditorIfNeeded(openEditor: () -> Void) {
        guard !didRequestEditor else { return }
        guard !HostsFileAccess.hasValidBookmark() else { return }
        didRequestEditor = true
        openEditor()
    }

    /// Presents step 1 once per launch when no valid bookmark exists.
    func startIfNeeded() {
        guard !didAutoPresent else { return }
        guard !HostsFileAccess.hasValidBookmark() else { return }
        didAutoPresent = true
        showAuthorize()
    }

    /// Step 1. Also used by the "授权…" toolbar button.
    func showAuthorize() {
        authorizeRetries = 0
        waitingForWindow = false
        presentAuthorize()
    }

    // MARK: - Authorize

    private func presentAuthorize() {
        guard !isPresenting else { return }
        guard let window = editorWindow() else {
            scheduleAuthorizeRetry()
            return
        }
        waitingForWindow = false
        authorizeRetries = 0
        let alert = NSAlert()
        alert.alertStyle = .informational
        applyAppIcon(to: alert)
        alert.messageText = "一次性写入授权"
        alert.informativeText = "需要一次性允许当前用户写入 /private/etc/hosts。在终端运行下面的命令，然后点「我已运行」。"
        alert.accessoryView = commandField(Self.grantCommand)
        alert.addButton(withTitle: "拷贝命令并打开终端")
        alert.addButton(withTitle: "我已运行")
        alert.addButton(withTitle: "稍后")
        // First button is NSAlert's default. Move Return to「我已运行」without
        // reordering the buttons or the help button.
        useReturnKey(for: "我已运行", on: alert)
        alert.showsHelp = true
        alert.delegate = self
        beginSheet(alert, on: window, then: finishAuthorize)
    }

    private func scheduleAuthorizeRetry() {
        guard !waitingForWindow else { return }
        authorizeRetries += 1
        guard authorizeRetries <= 20 else { return }
        waitingForWindow = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            Task { @MainActor in
                AppStoreOnboarding.shared.waitingForWindow = false
                AppStoreOnboarding.shared.presentAuthorize()
            }
        }
    }

    private func finishAuthorize(_ raw: Int) {
        switch raw {
        case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue:
            copyGrantCommand()
            openTerminal()
            presentAuthorize()
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
            continueAfterAuthorize()
        default:
            break
        }
    }

    /// Return /「我已运行」. An existing bookmark is probed immediately.
    /// Otherwise the file panel runs, and a failed write check ends on failure.
    private func continueAfterAuthorize() {
        if HostsFileAccess.hasValidBookmark() {
            recheckWriteAccess()
        } else {
            presentOpenPanel()
        }
    }

    /// Menu-bar apps (`LSUIElement`) leave `NSAlert`'s default icon as an empty
    /// 128pt well. The asset catalog image is what screen 1b already draws.
    private func applyAppIcon(to alert: NSAlert) {
        let source = NSImage(named: NSImage.applicationIconName)
            ?? NSImage(named: "AppIcon")
            ?? NSApp.applicationIconImage
        guard let icon = source?.copy() as? NSImage else {
            alert.icon = NSApp.applicationIconImage
            return
        }
        icon.size = NSSize(width: 128, height: 128)
        alert.icon = icon
    }

    private func useReturnKey(for buttonTitle: String, on alert: NSAlert) {
        for button in alert.buttons {
            button.keyEquivalent = button.title == buttonTitle ? "\r" : ""
        }
    }

    func alertShowHelp(_ alert: NSAlert) -> Bool {
        guard alert.showsHelp else { return false }
        let help = NSAlert()
        help.alertStyle = .informational
        applyAppIcon(to: help)
        help.messageText = "撤销写入权限"
        help.informativeText = "在终端运行下面的命令："
        help.accessoryView = commandField(Self.revokeCommand)
        help.addButton(withTitle: "好")
        help.runModal()
        return true
    }

    private func copyGrantCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.grantCommand, forType: .string)
    }

    private func openTerminal() {
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        _ = workspace.open(appURL)
    }

    // MARK: - Pick file

    private func presentOpenPanel() {
        guard let window = editorWindow() else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/private/etc", isDirectory: true)
        panel.showsHiddenFiles = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "授权"
        panel.message = "请选择 hosts 文件（/private/etc/hosts）。"
        retainedPanel = panel
        isPresenting = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            let raw = response.rawValue
            // Stay on this turn so the security-scoped URL is still valid for the bookmark.
            MainActor.assumeIsolated {
                let onboarding = AppStoreOnboarding.shared
                let url = onboarding.retainedPanel?.url
                onboarding.retainedPanel = nil
                onboarding.isPresenting = false
                onboarding.finishPanel(raw: raw, url: url)
            }
        }
    }

    private func finishPanel(raw: Int, url: URL?) {
        guard raw == NSApplication.ModalResponse.OK.rawValue, let url else { return }
        var failure: String?
        if !isHostsFile(url) {
            failure = "所选文件不是 /private/etc/hosts。"
        } else {
            do {
                try HostsFileAccess.grantHostsFileAccess(to: url)
                try HostsFileAccess.probeWriteAccess()
            } catch {
                failure = error.localizedDescription
            }
            onFinished?()
        }
        showPanelResult(failure)
    }

    private func showPanelResult(_ failure: String?) {
        isPresenting = true
        DispatchQueue.main.async {
            Task { @MainActor in
                AppStoreOnboarding.shared.isPresenting = false
                if let failure {
                    AppStoreOnboarding.shared.presentFailure(message: failure)
                } else {
                    AppStoreOnboarding.shared.presentDone()
                }
            }
        }
    }

    private func isHostsFile(_ url: URL) -> Bool {
        let selected = url.standardizedFileURL.path
        if selected == "/etc/hosts" || selected == HostsFileAccess.hostsPath {
            return true
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path == HostsFileAccess.hostsPath
    }

    // MARK: - Done and failure

    private func presentDone() {
        guard let window = editorWindow() else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        applyAppIcon(to: alert)
        alert.messageText = "授权已完成"
        alert.informativeText = "hosts 文件已可写入。如需刷新系统缓存，在终端运行："
        alert.accessoryView = commandField(Self.flushCommand)
        // NSAlert dismisses on every button. Copy, then show this sheet again.
        alert.addButton(withTitle: "拷贝命令")
        alert.addButton(withTitle: "好")
        useReturnKey(for: "好", on: alert)
        beginSheet(alert, on: window, then: finishDone)
    }

    private func finishDone(_ raw: Int) {
        guard raw == NSApplication.ModalResponse.alertFirstButtonReturn.rawValue else { return }
        copyFlushCommand()
        presentDone()
    }

    private func copyFlushCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.flushCommand, forType: .string)
    }

    private func presentFailure(message: String) {
        guard let window = editorWindow() else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "授权失败"
        alert.informativeText = message
        alert.addButton(withTitle: "重试")
        alert.addButton(withTitle: "重新选择文件…")
        alert.addButton(withTitle: "取消")
        beginSheet(alert, on: window, then: finishFailure)
    }

    private func finishFailure(_ raw: Int) {
        switch raw {
        case NSApplication.ModalResponse.alertFirstButtonReturn.rawValue:
            recheckWriteAccess()
        case NSApplication.ModalResponse.alertSecondButtonReturn.rawValue:
            presentOpenPanel()
        default:
            break
        }
    }

    /// 「重试」: probe the bookmark already stored. Success opens Done.
    /// Failure shows this alert again and does not return to authorize.
    private func recheckWriteAccess() {
        do {
            try HostsFileAccess.probeWriteAccess()
            onFinished?()
            presentDone()
        } catch {
            onFinished?()
            presentFailure(message: error.localizedDescription)
        }
    }

    // MARK: - Sheet

    private func beginSheet(_ alert: NSAlert, on window: NSWindow, then handle: @escaping @MainActor (Int) -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        retainedAlert = alert
        sheetHandler = handle
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: window) { response in
            let raw = response.rawValue
            Task { @MainActor in
                let handler = AppStoreOnboarding.shared.sheetHandler
                AppStoreOnboarding.shared.sheetHandler = nil
                AppStoreOnboarding.shared.isPresenting = false
                AppStoreOnboarding.shared.retainedAlert = nil
                handler?(raw)
            }
        }
    }

    private func editorWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard window.isVisible || window.isMiniaturized else { return false }
            if window.title == "Hosts Editor" { return true }
            let identifier = window.identifier?.rawValue ?? ""
            return identifier == "editor"
        }
    }

    private func commandField(_ command: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: command)
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.lineBreakMode = .byCharWrapping
        field.maximumNumberOfLines = 2
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        let maxWidth: CGFloat = 480
        field.preferredMaxLayoutWidth = maxWidth
        let fitted = field.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let lineHeight = (field.font?.boundingRectForFont.height ?? 13) + 4
        let height = min(max(fitted.height, lineHeight), lineHeight * 2)
        let width = min(max(fitted.width, 160), maxWidth)
        field.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return field
    }
}
#endif
