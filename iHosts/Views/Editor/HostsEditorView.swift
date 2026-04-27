import SwiftUI
import AppKit

struct HostsEditorView: NSViewRepresentable {
    @Binding var text: String
    var onChange: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView.textStorage!)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HostsEditorView

        init(_ parent: HostsEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
        }

        func textStorage(_ storage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range: NSRange, changeInLength: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            highlight(storage)
        }

        func highlight(_ storage: NSTextStorage) {
            let full = NSRange(location: 0, length: storage.length)
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ]
            storage.addAttributes(defaultAttrs, range: full)

            let text = storage.string
            text.enumerateSubstrings(in: text.startIndex...,
                                     options: .byLines) { _, range, _, _ in
                let nsRange = NSRange(range, in: text)
                let line = String(text[range]).trimmingCharacters(in: .whitespaces)

                if line.hasPrefix("#") {
                    storage.addAttribute(.foregroundColor,
                                         value: NSColor.secondaryLabelColor,
                                         range: nsRange)
                    return
                }

                let parts = line.split(maxSplits: 2,
                                       whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 2 else { return }
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
