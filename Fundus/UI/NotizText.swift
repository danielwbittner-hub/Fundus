import SwiftUI
import AppKit

/// Zeigt den (Markdown-)Text einer Notiz formatiert an: **fett**, *kursiv*,
/// Aufzählungen („- ") und abhakbare Checklisten („- [ ] " / „- [x] ").
struct NotizInhalt: View {
    let text: String
    let font: Font
    let farbe: Color
    var platzhalter: String = ""
    let toggle: (Int) -> Void          // Checklisten-Zeile i an-/abhaken

    private var zeilen: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        if text.isEmpty {
            Text(platzhalter).font(font).foregroundStyle(farbe.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(zeilen.enumerated()), id: \.offset) { i, z in
                    zeile(i, z)
                }
            }
            .font(font)
            .foregroundStyle(farbe)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func zeile(_ i: Int, _ z: String) -> some View {
        if let (an, rest) = Self.checkliste(z) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Button { toggle(i) } label: {
                    Image(systemName: an ? "checkmark.square.fill" : "square")
                        .foregroundStyle(an ? AnyShapeStyle(Design.neonCyan) : AnyShapeStyle(farbe.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .help(an ? "Häkchen entfernen" : "Abhaken")
                inline(rest).strikethrough(an, color: farbe.opacity(0.6))
                    .opacity(an ? 0.6 : 1)
                Spacer(minLength: 0)
            }
        } else if let rest = Self.aufzaehlung(z) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                inline(rest)
                Spacer(minLength: 0)
            }
        } else if z.isEmpty {
            Text(" ")
        } else {
            inline(z)
        }
    }

    /// Inline-Markdown (fett/kursiv) – Rest bleibt als Klartext.
    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(
            markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }

    // MARK: Zeilen erkennen

    /// Checkliste: liefert (abgehakt, Resttext) oder nil.
    static func checkliste(_ z: String) -> (Bool, String)? {
        let t = z.drop(while: { $0 == " " })
        guard t.hasPrefix("- [") else { return nil }
        let nach = t.dropFirst(2)   // nach „- "
        if nach.hasPrefix("[ ] ") || nach == "[ ]" { return (false, String(nach.dropFirst(min(4, nach.count)))) }
        let lower = nach.lowercased()
        if lower.hasPrefix("[x] ") || lower == "[x]" { return (true, String(nach.dropFirst(min(4, nach.count)))) }
        return nil
    }

    /// Aufzählung („- "/„* "/„• "), aber KEINE Checkliste: liefert Resttext oder nil.
    static func aufzaehlung(_ z: String) -> String? {
        if checkliste(z) != nil { return nil }
        let t = z.drop(while: { $0 == " " })
        for marke in ["- ", "* ", "• "] where t.hasPrefix(marke) {
            return String(t.dropFirst(marke.count))
        }
        return nil
    }
}

/// AppKit-gestützter Editor für den Notiz-Rohtext (Markdown). Bietet echte
/// Textauswahl, über die die Formatierungsleiste **fett**/*kursiv*/Listen setzt.
struct RichNotizEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var befehl: NotizFormat?
    var groesse: CGFloat
    var farbe: NSColor
    var fokusBeiStart: Bool = true
    var onEnde: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: groesse)
        tv.textColor = farbe
        tv.insertionPointColor = farbe
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        context.coordinator.textView = tv

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none

        if fokusBeiStart {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        if tv.font?.pointSize != groesse { tv.font = .systemFont(ofSize: groesse) }
        tv.textColor = farbe
        tv.insertionPointColor = farbe
        if let b = befehl {
            context.coordinator.wende(b, auf: tv)
            DispatchQueue.main.async {
                self.befehl = nil
                self.text = tv.string
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNotizEditor
        weak var textView: NSTextView?
        init(_ p: RichNotizEditor) { parent = p }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
        }
        func textDidEndEditing(_ note: Notification) { parent.onEnde() }

        func wende(_ b: NotizFormat, auf tv: NSTextView) {
            switch b {
            case .fett:       umschliesse(tv, "**")
            case .kursiv:     umschliesse(tv, "*")
            case .liste:      zeilenPrefix(tv, "- ")
            case .checkliste: zeilenPrefix(tv, "- [ ] ")
            }
        }

        /// Auswahl mit einer Marke umschließen (oder Marken am Cursor einsetzen).
        private func umschliesse(_ tv: NSTextView, _ marke: String) {
            let s = tv.string as NSString
            let sel = tv.selectedRange()
            let innen = s.substring(with: sel)
            let neu = marke + innen + marke
            if tv.shouldChangeText(in: sel, replacementString: neu) {
                tv.replaceCharacters(in: sel, with: neu)
                tv.didChangeText()
            }
            let m = (marke as NSString).length
            if innen.isEmpty {
                tv.setSelectedRange(NSRange(location: sel.location + m, length: 0))
            } else {
                tv.setSelectedRange(NSRange(location: sel.location + m, length: (innen as NSString).length))
            }
        }

        /// Jede Zeile der Auswahl (bzw. die Cursorzeile) mit einem Präfix versehen.
        private func zeilenPrefix(_ tv: NSTextView, _ prefix: String) {
            let s = tv.string as NSString
            let bereich = s.lineRange(for: tv.selectedRange())
            let block = s.substring(with: bereich)
            let hatNL = block.hasSuffix("\n")
            var zeilen = block.components(separatedBy: "\n")
            if hatNL { zeilen.removeLast() }
            zeilen = zeilen.map { prefix + $0 }
            var neu = zeilen.joined(separator: "\n")
            if hatNL { neu += "\n" }
            if tv.shouldChangeText(in: bereich, replacementString: neu) {
                tv.replaceCharacters(in: bereich, with: neu)
                tv.didChangeText()
            }
        }
    }
}
