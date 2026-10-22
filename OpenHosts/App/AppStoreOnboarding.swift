#if APPSTORE
import AppKit

/// First-launch write permission for the Mac App Store build.
///
/// Opaque document-modal sheets only. The Developer ID target does not compile this.
@MainActor
final class AppStoreOnboarding: NSObject {
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
    private var retainedSheet: NSWindow?
    private var retainedHelpSheet: NSWindow?
    private var helpParent: NSWindow?
    /// True when the help sheet itself is the document sheet, not a nested sheet.
    private var helpOwnsPresenting = false
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
        guard editorWindow() != nil else {
            scheduleAuthorizeRetry()
            return
        }
        waitingForWindow = false
        authorizeRetries = 0
        present(makeAuthorizeSheet(), then: finishAuthorize)
    }

    private func makeAuthorizeSheet() -> NSWindow {
        // 稍后 is leading. 拷贝命令 sits left of the Return button「我已运行」.
        makeSheet(
            icon: appIconImage(),
            message: "一次性写入授权",
            informative: "需要一次性允许当前用户写入 /private/etc/hosts。在终端运行下面的命令，然后点「我已运行」。",
            command: Self.grantCommand,
            showsHelp: true,
            buttons: [
                SheetButton(title: "稍后", response: .alertThirdButtonReturn, isDefault: false),
                SheetButton(title: "拷贝命令并打开终端", response: .alertFirstButtonReturn, isDefault: false),
                SheetButton(title: "我已运行", response: .alertSecondButtonReturn, isDefault: true),
            ]
        )
    }

    private func scheduleAuthorizeRetry() {
        guard !waitingForWindow else { return }
        authorizeRetries += 1
        if authorizeRetries > 20 {
            // The editor never appeared. Still show an opaque app-modal dialog.
            guard !isPresenting else { return }
            beginAppModal(makeAuthorizeSheet(), then: finishAuthorize)
            return
        }
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

    /// Menu-bar apps (`LSUIElement`) have no default document icon unless one is copied in.
    private func appIconImage() -> NSImage {
        let source = NSImage(named: NSImage.applicationIconName)
            ?? NSImage(named: "AppIcon")
            ?? NSApp.applicationIconImage
        guard let icon = source?.copy() as? NSImage else {
            return NSImage(size: NSSize(width: 128, height: 128))
        }
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }

    private func cautionIcon() -> NSImage {
        guard let icon = NSImage(named: NSImage.cautionName)?.copy() as? NSImage else {
            return appIconImage()
        }
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }

    /// ? on sheet 1. Nested on that sheet so the editor stays blocked and sheet 1 stays up.
    @objc private func showRevokeHelp(_ sender: NSButton) {
        presentRevokeHelp(preferredParent: sender.window)
    }

    /// Help with no sheet up attaches to the editor. Never attaches to the editor while sheet 1 is up.
    private func presentRevokeHelp(preferredParent: NSWindow?) {
        guard retainedHelpSheet == nil else { return }
        let sheet = makeHelpSheet()
        if let parent = preferredParent {
            beginHelpSheet(sheet, on: parent)
            return
        }
        if let authorize = retainedSheet {
            beginHelpSheet(sheet, on: authorize)
            return
        }
        if let editor = editorWindow() {
            beginHelpSheet(sheet, on: editor)
            return
        }
        beginHelpAppModal(sheet)
    }

    private func makeHelpSheet() -> NSWindow {
        makeSheet(
            icon: appIconImage(),
            message: "撤销写入权限",
            informative: "在终端运行下面的命令：",
            command: Self.revokeCommand,
            showsHelp: false,
            buttons: [
                SheetButton(title: "好", response: .alertFirstButtonReturn, isDefault: true),
            ]
        )
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
        present(makeDoneSheet(), then: finishDone)
    }

    private func makeDoneSheet() -> NSWindow {
        makeSheet(
            icon: appIconImage(),
            message: "授权已完成",
            informative: "hosts 文件已可写入。如需刷新系统缓存，在终端运行：",
            command: Self.flushCommand,
            showsHelp: false,
            buttons: [
                SheetButton(title: "拷贝命令", response: .alertFirstButtonReturn, isDefault: false),
                SheetButton(title: "好", response: .alertSecondButtonReturn, isDefault: true),
            ]
        )
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
        present(makeFailureSheet(message: message), then: finishFailure)
    }

    private func makeFailureSheet(message: String) -> NSWindow {
        makeSheet(
            icon: cautionIcon(),
            message: "授权失败",
            informative: message,
            command: nil,
            showsHelp: false,
            buttons: [
                SheetButton(title: "取消", response: .alertThirdButtonReturn, isDefault: false),
                SheetButton(title: "重新选择文件…", response: .alertSecondButtonReturn, isDefault: false),
                SheetButton(title: "重试", response: .alertFirstButtonReturn, isDefault: true),
            ]
        )
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

    // MARK: - Opaque sheet

    private struct SheetButton {
        let title: String
        let response: NSApplication.ModalResponse
        let isDefault: Bool
    }

    /// Document-modal on the editor. App-modal only when that window does not exist.
    private func present(_ sheet: NSWindow, then handle: @escaping @MainActor (Int) -> Void) {
        guard !isPresenting else { return }
        if let window = editorWindow() {
            beginDocumentSheet(sheet, on: window, then: handle)
        } else {
            beginAppModal(sheet, then: handle)
        }
    }

    private func beginDocumentSheet(_ sheet: NSWindow, on window: NSWindow, then handle: @escaping @MainActor (Int) -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        retainedSheet = sheet
        sheetHandler = handle
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.beginSheet(sheet) { response in
            let raw = response.rawValue
            Task { @MainActor in
                let handler = AppStoreOnboarding.shared.sheetHandler
                AppStoreOnboarding.shared.sheetHandler = nil
                AppStoreOnboarding.shared.isPresenting = false
                AppStoreOnboarding.shared.retainedSheet = nil
                handler?(raw)
            }
        }
    }

    private func beginAppModal(_ sheet: NSWindow, then handle: @escaping @MainActor (Int) -> Void) {
        guard !isPresenting else { return }
        isPresenting = true
        retainedSheet = sheet
        sheet.level = .modalPanel
        sheet.center()
        NSApp.activate(ignoringOtherApps: true)
        sheet.makeKeyAndOrderFront(nil)
        let response = NSApp.runModal(for: sheet)
        sheet.orderOut(nil)
        retainedSheet = nil
        isPresenting = false
        handle(response.rawValue)
    }

    /// Nested when `parent` is sheet 1. Does not end that sheet or clear its presenting flag.
    private func beginHelpSheet(_ sheet: NSWindow, on parent: NSWindow) {
        let ownsPresenting = !isPresenting
        if ownsPresenting {
            isPresenting = true
        }
        retainedHelpSheet = sheet
        helpParent = parent
        helpOwnsPresenting = ownsPresenting
        parent.beginSheet(sheet) { _ in
            Task { @MainActor in
                let onboarding = AppStoreOnboarding.shared
                let parent = onboarding.helpParent
                let owns = onboarding.helpOwnsPresenting
                onboarding.retainedHelpSheet = nil
                onboarding.helpParent = nil
                onboarding.helpOwnsPresenting = false
                if owns {
                    onboarding.isPresenting = false
                }
                if let parent {
                    onboarding.restoreDefaultButton(on: parent)
                }
            }
        }
    }

    private func beginHelpAppModal(_ sheet: NSWindow) {
        guard !isPresenting else { return }
        isPresenting = true
        retainedHelpSheet = sheet
        sheet.level = .modalPanel
        sheet.center()
        NSApp.activate(ignoringOtherApps: true)
        sheet.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: sheet)
        sheet.orderOut(nil)
        retainedHelpSheet = nil
        isPresenting = false
    }

    /// Puts Return back on the parent's default button after a nested sheet closes.
    private func restoreDefaultButton(on window: NSWindow) {
        guard let button = returnButton(in: window.contentView) else { return }
        if let cell = button.cell as? NSButtonCell {
            window.defaultButtonCell = cell
        }
        window.makeFirstResponder(button)
    }

    private func returnButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.keyEquivalent == "\r" {
            return button
        }
        for subview in view.subviews {
            if let found = returnButton(in: subview) {
                return found
            }
        }
        return nil
    }

    @objc private func sheetButtonClicked(_ sender: NSButton) {
        let code = NSApplication.ModalResponse(rawValue: sender.tag)
        guard let window = sender.window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window, returnCode: code)
        } else {
            window.orderOut(nil)
            NSApp.stopModal(withCode: code)
        }
    }

    private func makeSheet(
        icon: NSImage,
        message: String,
        informative: String,
        command: String?,
        showsHelp: Bool,
        buttons: [SheetButton]
    ) -> NSWindow {
        let columnWidth: CGFloat
        let commandView: NSTextField?
        if let command {
            let field = commandField(command)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: field.frame.width).isActive = true
            field.heightAnchor.constraint(equalToConstant: field.frame.height).isActive = true
            commandView = field
            columnWidth = max(field.frame.width, 320)
        } else {
            commandView = nil
            columnWidth = 420
        }

        let messageField = NSTextField(wrappingLabelWithString: message)
        messageField.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        messageField.textColor = .labelColor
        messageField.preferredMaxLayoutWidth = columnWidth
        messageField.maximumNumberOfLines = 2
        messageField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let infoField = NSTextField(wrappingLabelWithString: informative)
        infoField.font = .systemFont(ofSize: NSFont.systemFontSize)
        infoField.textColor = .labelColor
        infoField.preferredMaxLayoutWidth = columnWidth
        infoField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textColumn = NSStackView()
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 8
        textColumn.addArrangedSubview(messageField)
        textColumn.addArrangedSubview(infoField)
        if let commandView {
            textColumn.addArrangedSubview(commandView)
        }
        textColumn.widthAnchor.constraint(equalToConstant: columnWidth).isActive = true

        let iconView = NSImageView()
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignTop
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 128).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 128).isActive = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .top
        header.spacing = 18
        header.addArrangedSubview(iconView)
        header.addArrangedSubview(textColumn)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8
        buttonRow.distribution = .fill
        if showsHelp {
            let help = NSButton()
            help.bezelStyle = .helpButton
            help.title = ""
            help.target = self
            help.action = #selector(showRevokeHelp(_:))
            buttonRow.addArrangedSubview(help)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        buttonRow.addArrangedSubview(spacer)

        var defaultButton: NSButton?
        for spec in buttons {
            let button = NSButton(title: spec.title, target: self, action: #selector(sheetButtonClicked(_:)))
            button.bezelStyle = .rounded
            button.tag = spec.response.rawValue
            button.keyEquivalent = spec.isDefault ? "\r" : ""
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
            buttonRow.addArrangedSubview(button)
            if spec.isDefault {
                defaultButton = button
            }
        }
        buttonRow.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 20
        outer.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        outer.addArrangedSubview(header)
        outer.addArrangedSubview(buttonRow)

        let window = makeOpaqueWindow(fitting: outer)
        if let defaultButton, let cell = defaultButton.cell as? NSButtonCell {
            window.defaultButtonCell = cell
            window.initialFirstResponder = defaultButton
        }
        return window
    }

    /// Public opacity only: an opaque window background, no visual-effect view.
    private func makeOpaqueWindow(fitting content: NSView) -> NSWindow {
        let window = OpaqueSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false

        let background = OpaqueSheetView()
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        window.contentView = background
        background.layoutSubtreeIfNeeded()
        let fitted = background.fittingSize
        let size = NSSize(
            width: max(fitted.width, 360),
            height: max(fitted.height, 180)
        )
        window.setContentSize(size)
        return window
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
        field.backgroundColor = .textBackgroundColor
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

/// Borderless windows cannot become key unless asked. Return needs a key window.
private final class OpaqueSheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Fills the sheet with the opaque window background in both appearances.
private final class OpaqueSheetView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.isOpaque = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
#endif
