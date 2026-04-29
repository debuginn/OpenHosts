import SwiftUI
import AppKit

struct HostsEditorView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        let tabWidth: CGFloat = 8
        let charWidth = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            .advancement(forGlyph: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular).glyph(withName: "space")).width
        let tabInterval = charWidth * tabWidth
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = tabInterval
        paragraph.tabStops = (0..<20).map { NSTextTab(textAlignment: .left, location: tabInterval * CGFloat($0 + 1)) }
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        if !isEditable {
            textView.backgroundColor = NSColor.windowBackgroundColor
        }
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.string = text
        context.coordinator.highlight(textView.textStorage!)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            context.coordinator.highlight(textView.textStorage!)
            if sel.location <= text.utf16.count {
                textView.setSelectedRange(sel)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HostsEditorView

        init(_ parent: HostsEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textStorage(_ storage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            highlight(storage)
        }

        func highlight(_ storage: NSTextStorage) {
            let full = NSRange(location: 0, length: storage.length)
            storage.addAttributes([
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .underlineStyle: 0,
            ], range: full)

            let text = storage.string
            text.enumerateSubstrings(in: text.startIndex..., options: .byLines) { _, range, _, _ in
                let nsRange = NSRange(range, in: text)
                let line = String(text[range]).trimmingCharacters(in: .whitespaces)

                if line.isEmpty { return }

                if line.hasPrefix("#") {
                    storage.addAttribute(.foregroundColor,
                                         value: NSColor.secondaryLabelColor,
                                         range: nsRange)
                    return
                }

                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })

                if !HostsValidator.isValidHostsLine(parts) {
                    storage.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                        .underlineColor: NSColor.systemRed,
                    ], range: nsRange)
                    return
                }

                let ipStr = String(parts[0])
                if let ipRange = text.range(of: ipStr, range: range) {
                    storage.addAttribute(.foregroundColor,
                                         value: NSColor.systemBlue,
                                         range: NSRange(ipRange, in: text))
                }
            }
        }

    }
}
