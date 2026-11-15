import Foundation

/// Erstellt ein weitergebbares „Fundus-Paket": kopiert die referenzierten Dateien
/// in einen Ordner und legt ein Manifest (Markdown + JSON) mit allen Objekten,
/// Schlagworten, Notizen und Web-Links dazu. Originaldateien bleiben unberührt.
enum Paket {

    static func exportiere(eintraege: [Eintrag], boardName: String, ziel: URL)
        -> (ok: Bool, ordner: URL?, meldung: String) {
        let fm = FileManager.default
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmm"
        let sauber = boardName.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let wurzel = ziel.appendingPathComponent("Fundus-\(sauber)-\(f.string(from: Date()))", isDirectory: true)
        let dateiOrdner = wurzel.appendingPathComponent("Dateien", isDirectory: true)
        do { try fm.createDirectory(at: dateiOrdner, withIntermediateDirectories: true) }
        catch { return (false, nil, "Zielordner ließ sich nicht anlegen.") }

        var benutzt = Set<String>()
        var kopiert = 0
        var dateiZeilen: [String] = []
        var linkZeilen: [String] = []
        var json: [[String: Any]] = []

        for e in eintraege {
            var relativ: String? = nil
            if (e.istDatei || e.istOrdnerRef), fm.fileExists(atPath: e.pfad) {
                let zielName = eindeutig(e.url.lastPathComponent, benutzt: &benutzt)
                let kopie = dateiOrdner.appendingPathComponent(zielName)
                if (try? fm.copyItem(at: e.url, to: kopie)) != nil {
                    kopiert += 1
                    relativ = "Dateien/\(zielName)"
                }
            }
            let tags = e.tagListe.map { "#\($0)" }.joined(separator: " ")
            var obj: [String: Any] = ["name": e.name, "typ": e.kategorie.rawValue, "pfad": e.pfad]
            if !tags.isEmpty { obj["tags"] = e.tagListe }
            if !e.kommentar.isEmpty { obj["notiz"] = e.kommentar }
            if let r = relativ { obj["datei"] = r }
            json.append(obj)

            if e.istWeblink {
                var z = "- [\(e.name)](\(e.pfad))"
                if !e.kommentar.isEmpty { z += " — \(e.kommentar)" }
                if !tags.isEmpty { z += "  \(tags)" }
                linkZeilen.append(z)
            } else {
                var z = "- **\(e.name)**"
                if let r = relativ { z += " → `\(r)`" } else { z += " _(nicht gefunden)_" }
                z += "  \n  Pfad: `\(e.pfad)`"
                if !tags.isEmpty { z += "  \n  Schlagworte: \(tags)" }
                if !e.kommentar.isEmpty { z += "  \n  Notiz: \(e.kommentar)" }
                dateiZeilen.append(z)
            }
        }

        var md = "# Fundus-Paket – \(boardName)\n\n"
        md += "Erstellt: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        md += "\(eintraege.count) Objekte · \(kopiert) Datei(en) kopiert.\n"
        if !dateiZeilen.isEmpty { md += "\n## Dateien & Objekte\n\n" + dateiZeilen.joined(separator: "\n") + "\n" }
        if !linkZeilen.isEmpty { md += "\n## Web-Links\n\n" + linkZeilen.joined(separator: "\n") + "\n" }

        try? md.data(using: .utf8)?.write(to: wurzel.appendingPathComponent("Manifest.md"))
        if let jd = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? jd.write(to: wurzel.appendingPathComponent("Manifest.json"))
        }
        return (true, wurzel, "Paket erstellt: \(kopiert) Datei(en) + Manifest")
    }

    /// Dateiname eindeutig machen (name, name-2, name-3 …).
    private static func eindeutig(_ name: String, benutzt: inout Set<String>) -> String {
        guard benutzt.contains(name.lowercased()) else { benutzt.insert(name.lowercased()); return name }
        let basis = (name as NSString).deletingPathExtension
        let endung = (name as NSString).pathExtension
        var i = 2
        while true {
            let kandidat = endung.isEmpty ? "\(basis)-\(i)" : "\(basis)-\(i).\(endung)"
            if !benutzt.contains(kandidat.lowercased()) { benutzt.insert(kandidat.lowercased()); return kandidat }
            i += 1
        }
    }
}
