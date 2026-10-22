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
        // NSAlert's narrow vertical stack: Return button on top, help in the corner.
        makeSheet(
            icon: appIconImage(),
            message: "一次性写入授权",
            informative: "需要一次性允许当前用户写入 /private/etc/hosts。在终端运行下面的命令，然后点「我已运行」。",
            command: Self.grantCommand,
            showsHelp: true,
            layout: .vertical,
            buttons: [
                SheetButton(title: "我已运行", response: .alertSecondButtonReturn, isDefault: true),
                SheetButton(title: "拷贝命令并打开终端", response: .alertFirstButtonReturn, isDefault: false),
                SheetButton(title: "稍后", response: .alertThirdButtonReturn, isDefault: false),
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

    /// Critical NSAlert icon: a 64pt caution triangle with a 32pt app-icon badge.
    /// Drawn at 128pt so the 64pt image view stays sharp.
    private func criticalAlertIcon() -> NSImage {
        let side: CGFloat = 128
        let badgeSide: CGFloat = 64
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSImage(named: NSImage.cautionName)?.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        appIconImage().draw(
            in: NSRect(x: side - badgeSide, y: 0, width: badgeSide, height: badgeSide),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        return image
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
            layout: .vertical,
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
            layout: .horizontal,
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
            icon: criticalAlertIcon(),
            message: "授权失败",
            informative: message,
            command: nil,
            showsHelp: false,
            layout: .vertical,
            buttons: [
                SheetButton(title: "重试", response: .alertFirstButtonReturn, isDefault: true),
                SheetButton(title: "重新选择文件…", response: .alertSecondButtonReturn, isDefault: false),
                SheetButton(title: "取消", response: .alertThirdButtonReturn, isDefault: false),
            ],
            windowWidth: AlertMetrics.failureWindowWidth
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

    /// Vertical matches NSAlert when the buttons do not fit in one row.
    private enum SheetButtonLayout {
        case vertical
        case horizontal
    }

    /// These constants mirror the measured NSAlert metrics.
    /// Wide sheets are 459×325 / 459×240. The critical failure sheet is 260×303.
    /// Icon and labels sit at x 20. The command field is 427×22 at x 16.
    /// Buttons are a 228pt column: a vertical stack, or one equal-width row.
    private enum AlertMetrics {
        static let windowWidth: CGFloat = 459
        static let failureWindowWidth: CGFloat = 260
        static let marginH: CGFloat = 16
        static let marginTop: CGFloat = 20
        static let marginBottom: CGFloat = 16
        static let iconSide: CGFloat = 64
        /// 16pt column margin plus this inset puts the icon and labels at x 20.
        static let textInset: CGFloat = 4
        static let iconTitleSpacing: CGFloat = 16
        static let titleInfoSpacing: CGFloat = 10
        static let fieldSpacing: CGFloat = 16
        static let buttonTopSpacing: CGFloat = 16
        static let buttonSpacing: CGFloat = 6
        static let horizontalButtonSpacing: CGFloat = 8
        static let buttonColumnWidth: CGFloat = 228
        static let buttonHeight: CGFloat = 28
        static let fieldHeight: CGFloat = 22
        static let infoLineHeight: CGFloat = 16
        static let helpTop: CGFloat = 12
        static let helpTrailing: CGFloat = 12
        static let helpSide: CGFloat = 28
        static var contentWidth: CGFloat { windowWidth - marginH * 2 }
        static var textWidth: CGFloat { contentWidth - textInset * 2 }
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

    /// NSAlert multi-line informative text is 16pt per line plus 0.5 (2 lines = 32.5, 3 = 48.5).
    private func alertInformativeHeight(fitting field: NSTextField, width: CGFloat) -> CGFloat {
        let line = AlertMetrics.infoLineHeight
        let fitted = field.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        let lines = max(1, Int((fitted.height / line).rounded()))
        if lines > 1 {
            return CGFloat(lines) * line + 0.5
        }
        return line
    }

    private func makeSheet(
        icon: NSImage,
        message: String,
        informative: String,
        command: String?,
        showsHelp: Bool,
        layout: SheetButtonLayout,
        buttons: [SheetButton],
        windowWidth: CGFloat = AlertMetrics.windowWidth
    ) -> NSWindow {
        let contentWidth = windowWidth - AlertMetrics.marginH * 2
        let textWidth = contentWidth - AlertMetrics.textInset * 2

        let messageField = AlertLabelField(wrappingLabelWithString: message)
        messageField.font = .boldSystemFont(ofSize: 13)
        messageField.textColor = .labelColor
        messageField.preferredMaxLayoutWidth = textWidth
        messageField.maximumNumberOfLines = 2
        messageField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        messageField.widthAnchor.constraint(equalToConstant: textWidth).isActive = true

        let infoField = AlertLabelField(wrappingLabelWithString: informative)
        infoField.font = .systemFont(ofSize: 13)
        infoField.textColor = .labelColor
        infoField.preferredMaxLayoutWidth = textWidth
        infoField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoField.setContentHuggingPriority(.required, for: .vertical)
        infoField.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        let infoHeight = alertInformativeHeight(fitting: infoField, width: textWidth)
        infoField.heightAnchor.constraint(equalToConstant: infoHeight).isActive = true
        // The wrapped field is already 16n+0.5. That half point belongs in the top margin, not under the text.
        let topMargin = AlertMetrics.marginTop + (infoHeight > AlertMetrics.infoLineHeight ? 0.5 : 0)

        let iconView = NSImageView()
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: AlertMetrics.iconSide).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: AlertMetrics.iconSide).isActive = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)

        let messageBlock = NSStackView()
        messageBlock.orientation = .vertical
        messageBlock.alignment = .leading
        messageBlock.spacing = 0
        messageBlock.addArrangedSubview(iconView)
        messageBlock.setCustomSpacing(AlertMetrics.iconTitleSpacing, after: iconView)
        messageBlock.addArrangedSubview(messageField)
        messageBlock.setCustomSpacing(AlertMetrics.titleInfoSpacing, after: messageField)
        messageBlock.addArrangedSubview(infoField)

        let messageHost = NSView()
        messageBlock.translatesAutoresizingMaskIntoConstraints = false
        messageHost.addSubview(messageBlock)
        NSLayoutConstraint.activate([
            messageBlock.leadingAnchor.constraint(equalTo: messageHost.leadingAnchor, constant: AlertMetrics.textInset),
            messageBlock.topAnchor.constraint(equalTo: messageHost.topAnchor),
            messageBlock.bottomAnchor.constraint(equalTo: messageHost.bottomAnchor),
            messageBlock.widthAnchor.constraint(equalToConstant: textWidth),
        ])

        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.addArrangedSubview(messageHost)

        if let command {
            let field = commandField(command, maxWidth: contentWidth)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.setContentHuggingPriority(.init(1), for: .horizontal)
            field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            field.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            field.heightAnchor.constraint(equalToConstant: AlertMetrics.fieldHeight).isActive = true
            column.setCustomSpacing(AlertMetrics.fieldSpacing, after: messageHost)
            column.addArrangedSubview(field)
        }

        var defaultButton: NSButton?
        let buttonRow = NSStackView()
        buttonRow.orientation = layout == .vertical ? .vertical : .horizontal
        // AppKit alignment is an NSLayoutConstraint.Attribute. `.width` stretches
        // each vertical button to the 228pt row; `.centerY` is the horizontal row.
        buttonRow.alignment = layout == .vertical ? .width : .centerY
        buttonRow.distribution = layout == .horizontal ? .fillEqually : .fill
        buttonRow.spacing = layout == .vertical ? AlertMetrics.buttonSpacing : AlertMetrics.horizontalButtonSpacing
        for spec in buttons {
            let button = NSButton(title: spec.title, target: self, action: #selector(sheetButtonClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.heightAnchor.constraint(equalToConstant: AlertMetrics.buttonHeight).isActive = true
            button.tag = spec.response.rawValue
            button.keyEquivalent = spec.isDefault ? "\r" : ""
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            if layout == .vertical {
                button.widthAnchor.constraint(equalToConstant: AlertMetrics.buttonColumnWidth).isActive = true
            }
            buttonRow.addArrangedSubview(button)
            if spec.isDefault {
                defaultButton = button
            }
        }

        let buttonHost = NSView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonHost.addSubview(buttonRow)
        NSLayoutConstraint.activate([
            buttonRow.centerXAnchor.constraint(equalTo: buttonHost.centerXAnchor),
            buttonRow.topAnchor.constraint(equalTo: buttonHost.topAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: buttonHost.bottomAnchor),
            buttonRow.widthAnchor.constraint(equalToConstant: AlertMetrics.buttonColumnWidth),
        ])
        let aboveButtons = column.arrangedSubviews.last ?? messageHost
        column.setCustomSpacing(AlertMetrics.buttonTopSpacing, after: aboveButtons)
        column.addArrangedSubview(buttonHost)

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: windowWidth),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: AlertMetrics.marginH),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -AlertMetrics.marginH),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: topMargin),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -AlertMetrics.marginBottom),
            messageHost.widthAnchor.constraint(equalToConstant: contentWidth),
            buttonHost.widthAnchor.constraint(equalToConstant: contentWidth),
        ])
        if showsHelp {
            let help = NSButton()
            help.bezelStyle = .helpButton
            help.controlSize = .large
            help.title = ""
            help.target = self
            help.action = #selector(showRevokeHelp(_:))
            help.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(help)
            let helpTop = AlertMetrics.helpTop + (topMargin - AlertMetrics.marginTop)
            NSLayoutConstraint.activate([
                help.topAnchor.constraint(equalTo: root.topAnchor, constant: helpTop),
                help.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -AlertMetrics.helpTrailing),
                help.widthAnchor.constraint(equalToConstant: AlertMetrics.helpSide),
                help.heightAnchor.constraint(equalToConstant: AlertMetrics.helpSide),
            ])
        }

        let window = makeOpaqueWindow(fitting: root, width: windowWidth)
        if let defaultButton, let cell = defaultButton.cell as? NSButtonCell {
            window.defaultButtonCell = cell
            window.initialFirstResponder = defaultButton
        }
        return window
    }

    /// Public opacity only: an opaque window background, no visual-effect view.
    private func makeOpaqueWindow(fitting content: NSView, width: CGFloat) -> NSWindow {
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
            width: width,
            height: max(fitted.height, 120)
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

    private func commandField(_ command: String, maxWidth: CGFloat) -> NSTextField {
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
        field.preferredMaxLayoutWidth = maxWidth
        let fitted = field.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let lineHeight = (field.font?.boundingRectForFont.height ?? 13) + 4
        let height = min(max(fitted.height, lineHeight), lineHeight * 2)
        let width = min(max(fitted.width, 160), maxWidth)
        field.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return field
    }
}

/// Borderless label whose frame is the text rect. A stock NSTextField outsets that rect by 2pt, so the line would start at x 18 and wrap at 423 instead of x 20 / 419.
private final class AlertLabelField: NSTextField {
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
