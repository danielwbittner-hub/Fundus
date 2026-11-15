import Foundation

/// Sichert die Datenbank (und beim großen Backup auch Vorschauen/erfasste Dateien)
/// in einen gewählten Ordner – z. B. auf einem externen oder gemounteten
/// Netzlaufwerk. Läuft im Hintergrund.
enum Sicherung {

    /// Ist das Ziel erreichbar und beschreibbar (Netzlaufwerk gemountet)?
    static func erreichbar(_ url: URL) -> Bool {
        var istOrdner: ObjCBool = false
        let da = FileManager.default.fileExists(atPath: url.path, isDirectory: &istOrdner)
        return da && istOrdner.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }

    /// Führt eine Sicherung aus. `gross` = komplettes Wochen-Backup inkl. Ordner.
    static func sichere(quelle dbOrdner: URL, ziel: URL, gross: Bool,
                        vorschau: URL?, erfasst: URL?) -> (ok: Bool, meldung: String) {
        let fm = FileManager.default
        let db = dbOrdner.appendingPathComponent("Fundus.db")
        guard fm.fileExists(atPath: db.path) else { return (false, "Keine Datenbank gefunden.") }
        guard erreichbar(ziel) else { return (false, "Backup-Ziel nicht erreichbar.") }

        let wurzel = ziel.appendingPathComponent("Fundus-Sicherung", isDirectory: true)
        let stempel = zeitstempel()
        do {
            if gross {
                let ordner = wurzel.appendingPathComponent("woechentlich/Fundus-\(stempel)", isDirectory: true)
                try fm.createDirectory(at: ordner, withIntermediateDirectories: true)
                // Nach dem WAL-Checkpoint(TRUNCATE) ist Fundus.db in sich vollständig –
                // -wal/-shm NICHT mitkopieren (ein lebendes, nicht zur .db passendes
                // WAL würde die Wiederherstellung sonst verfälschen).
                try kopiere(db, ordner.appendingPathComponent("Fundus.db"))
                if let vo = vorschau, fm.fileExists(atPath: vo.path) {
                    try? kopiere(vo, ordner.appendingPathComponent(".vorschau"))
                }
                if let eo = erfasst, fm.fileExists(atPath: eo.path) {
                    try? kopiere(eo, ordner.appendingPathComponent(".erfasst"))
                }
                aufraeumen(wurzel.appendingPathComponent("woechentlich"), behalte: 8)
                return (true, "Wochen-Backup: \(ordner.lastPathComponent)")
            } else {
                let ordner = wurzel.appendingPathComponent("regelmaessig", isDirectory: true)
                try fm.createDirectory(at: ordner, withIntermediateDirectories: true)
                let datei = ordner.appendingPathComponent("Fundus-\(stempel).db")
                try kopiere(db, datei)
                aufraeumen(ordner, behalte: 10)
                return (true, "Backup: \(datei.lastPathComponent)")
            }
        } catch {
            return (false, "Backup fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    // MARK: Helfer

    private static func kopiere(_ von: URL, _ nach: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: nach.path) { try fm.removeItem(at: nach) }
        try fm.copyItem(at: von, to: nach)
    }

    /// Behält die `behalte` jüngsten Einträge und löscht den Rest.
    private static func aufraeumen(_ ordner: URL, behalte: Int) {
        let fm = FileManager.default
        guard let inhalte = try? fm.contentsOfDirectory(
            at: ordner, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let sortiert = inhalte.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }
        for alt in sortiert.dropFirst(behalte) { try? fm.removeItem(at: alt) }
    }

    private static func zeitstempel() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return f.string(from: Date())
    }
}
