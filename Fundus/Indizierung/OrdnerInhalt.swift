import Foundation

/// Liest den Inhalt eines referenzierten Finder-Ordners – einmal kompakt für die
/// Anzeige auf der Karte, einmal tief für den durchsuchbaren Volltext-Index.
enum OrdnerInhalt {

    struct Eintrag: Identifiable, Hashable {
        var name: String
        var istOrdner: Bool
        var id: String { (istOrdner ? "d:" : "f:") + name }
    }

    /// Oberste Ebene für die Karten-Vorschau in EINEM Verzeichnis-Listing:
    /// sortierte, gekürzte Liste PLUS Gesamtanzahl. Ordner zuerst, dann Dateien,
    /// jeweils alphabetisch; versteckte Dateien (Punkt) werden übersprungen.
    static func uebersicht(_ url: URL, maximal: Int = 80) -> (liste: [Eintrag], anzahl: Int) {
        let fm = FileManager.default
        guard let inhalte = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return ([], 0) }
        var liste = inhalte.map { kind -> Eintrag in
            let ist = (try? kind.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return Eintrag(name: kind.lastPathComponent, istOrdner: ist)
        }
        liste.sort { a, b in
            if a.istOrdner != b.istOrdner { return a.istOrdner && !b.istOrdner }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        return (Array(liste.prefix(maximal)), inhalte.count)
    }

    /// Alle Dateinamen (rekursiv, begrenzt) als ein Text-Block für den Volltext.
    /// So findet die Suche den Ordner auch über seinen Inhalt.
    static func indexText(_ url: URL, maxDateien: Int = 4000) -> String {
        let fm = FileManager.default
        guard let laeufer = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return url.lastPathComponent
        }
        var namen: [String] = [url.lastPathComponent]
        for fall in laeufer {
            guard let f = fall as? URL else { continue }
            namen.append(f.lastPathComponent)
            if namen.count >= maxDateien { break }
        }
        return namen.joined(separator: "\n")
    }
}
