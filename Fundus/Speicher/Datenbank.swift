import Foundation
import SQLite3
import os

/// Ein sehr schlanker Aufsatz auf SQLite – gerade genug, um Anweisungen mit
/// Parametern auszuführen und Zeilen zu lesen. Bewusst ohne Fremdpaket: die
/// Bibliothek steckt schon im System. Vorbild: Tafel (whiteboard/Mac-App).
///
/// Nicht nebenläufig: alle Zugriffe laufen über den Akteur `Ablage`.
final class Datenbank {
    private var griff: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let log = Logger(subsystem: "de.dwbkd.fundus", category: "datenbank")
    private var inTx = false      // läuft gerade eine Transaktion?
    private var txKaputt = false  // schlug darin eine Anweisung fehl? → ROLLBACK

    init(pfad: String) throws {
        if sqlite3_open(pfad, &griff) != SQLITE_OK {
            throw fehler("Datenbank ließ sich nicht öffnen")
        }
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA foreign_keys=ON;")
        exec("PRAGMA busy_timeout=3000;")
    }

    deinit { sqlite3_close(griff) }

    /// Anweisung ohne Rückgabe. Gibt zurück, ob sie fehlerfrei lief.
    @discardableResult
    func exec(_ sql: String) -> Bool {
        sqlite3_exec(griff, sql, nil, nil, nil) == SQLITE_OK
    }

    @discardableResult
    func schreibe(_ sql: String, _ werte: [Wert] = []) -> Bool {
        guard let stmt = bereite(sql, werte) else { if inTx { txKaputt = true }; return false }
        defer { sqlite3_finalize(stmt) }
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        if !ok {
            if inTx { txKaputt = true }
            Datenbank.log.error("DB-Schreibfehler: \(self.fehlertext(), privacy: .public)")
        }
        return ok
    }

    /// Letzte vergebene rowid (nach einem INSERT).
    var letzteID: Int { Int(sqlite3_last_insert_rowid(griff)) }

    func lies<T>(_ sql: String, _ werte: [Wert] = [], _ je: (Zeile) -> T) -> [T] {
        guard let stmt = bereite(sql, werte) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var ergebnis: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ergebnis.append(je(Zeile(stmt: stmt)))
        }
        return ergebnis
    }

    /// Führt `arbeit` in einer Transaktion aus. Schlägt darin eine Schreib-/
    /// Anweisung fehl, wird die GESAMTE Transaktion zurückgerollt statt einen
    /// halb geschriebenen Zustand zu committen.
    func inTransaktion(_ arbeit: () -> Void) {
        guard exec("BEGIN IMMEDIATE;") else { arbeit(); return }
        inTx = true; txKaputt = false
        arbeit()
        inTx = false
        if txKaputt {
            exec("ROLLBACK;")
            Datenbank.log.error("Transaktion zurückgerollt (Schreibfehler).")
        } else {
            exec("COMMIT;")
        }
    }

    /// Nextcloud-Freundlich: WAL in die Hauptdatei zurückschreiben, damit nur
    /// eine konsistente Datei synchronisiert wird.
    func checkpoint() {
        exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: intern

    private func bereite(_ sql: String, _ werte: [Wert]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(griff, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        for (i, w) in werte.enumerated() {
            let pos = Int32(i + 1)
            switch w {
            case .text(let s): sqlite3_bind_text(stmt, pos, s, -1, Datenbank.transient)
            case .ganz(let n): sqlite3_bind_int64(stmt, pos, Int64(n))
            case .komma(let d): sqlite3_bind_double(stmt, pos, d)
            case .leer:        sqlite3_bind_null(stmt, pos)
            }
        }
        return stmt
    }

    private func fehler(_ was: String) -> NSError {
        return NSError(domain: "Fundus.Datenbank", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: "\(was): \(fehlertext())"])
    }

    private func fehlertext() -> String {
        griff.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "?"
    }

    // MARK: Werte & Zeilen

    enum Wert {
        case text(String)
        case ganz(Int)
        case komma(Double)
        case leer
    }

    struct Zeile {
        let stmt: OpaquePointer?
        func text(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
        func textOpt(_ i: Int32) -> String? {
            guard let c = sqlite3_column_text(stmt, i) else { return nil }
            let s = String(cString: c)
            return s.isEmpty ? nil : s
        }
        func ganz(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func ganzOpt(_ i: Int32) -> Int? {
            sqlite3_column_type(stmt, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, i))
        }
        func komma(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    }
}
