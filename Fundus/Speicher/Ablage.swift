import Foundation

/// Besitzt die Datenbank und kapselt alle Zugriffe. Als Akteur: die Leinwand
/// (Haupt-Thread) und die Hintergrund-Indizierung greifen gefahrlos zu.
actor Ablage {
    private let db: Datenbank
    private var fts5 = true

    init(dbURL: URL) throws {
        let d = try Datenbank(pfad: dbURL.path)
        db = d
        fts5 = Ablage.schema(d)
    }

    func checkpoint() { db.checkpoint() }

    // MARK: Schema

    /// Legt die Tabellen an und meldet, ob FTS5 verfügbar ist. Nebenläufigkeits-frei
    /// (statisch), damit der Init-Aufruf keine Akteur-Isolation verletzt.
    private static func schema(_ db: Datenbank) -> Bool {
        db.exec("""
            CREATE TABLE IF NOT EXISTS board(
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              zoom REAL NOT NULL DEFAULT 1,
              offset_x REAL NOT NULL DEFAULT 0,
              offset_y REAL NOT NULL DEFAULT 0
            );
        """)
        db.exec("""
            CREATE TABLE IF NOT EXISTS eintrag(
              id INTEGER PRIMARY KEY,
              board_id INTEGER NOT NULL REFERENCES board(id) ON DELETE CASCADE,
              pfad TEXT NOT NULL,
              name TEXT NOT NULL,
              endung TEXT NOT NULL,
              kategorie TEXT NOT NULL,
              groesse INTEGER NOT NULL DEFAULT 0,
              datei_geaendert REAL NOT NULL DEFAULT 0,
              erstellt REAL NOT NULL DEFAULT 0,
              x REAL NOT NULL DEFAULT 0,
              y REAL NOT NULL DEFAULT 0,
              breite REAL NOT NULL DEFAULT 190,
              hoehe REAL NOT NULL DEFAULT 210,
              vorschau TEXT,
              idml_quelle TEXT,
              zustand TEXT NOT NULL DEFAULT 'ok',
              indiziert INTEGER NOT NULL DEFAULT 0,
              ordner_id INTEGER,
              farbe INTEGER NOT NULL DEFAULT 0,
              farbhex TEXT,
              symbol TEXT NOT NULL DEFAULT ''
            );
        """)
        // Migration für ältere DBs: Spalte nachrüsten (Fehler egal, falls vorhanden).
        db.exec("ALTER TABLE eintrag ADD COLUMN ordner_id INTEGER;")
        db.exec("ALTER TABLE eintrag ADD COLUMN kommentar TEXT NOT NULL DEFAULT '';")
        db.exec("ALTER TABLE eintrag ADD COLUMN tags TEXT NOT NULL DEFAULT '';")
        db.exec("ALTER TABLE eintrag ADD COLUMN lesezeichen TEXT;")
        db.exec("ALTER TABLE eintrag ADD COLUMN farbe INTEGER NOT NULL DEFAULT 0;")
        db.exec("ALTER TABLE eintrag ADD COLUMN farbhex TEXT;")
        db.exec("ALTER TABLE eintrag ADD COLUMN symbol TEXT NOT NULL DEFAULT '';")
        db.exec("""
            CREATE TABLE IF NOT EXISTS ordner(
              id INTEGER PRIMARY KEY,
              board_id INTEGER NOT NULL REFERENCES board(id) ON DELETE CASCADE,
              name TEXT NOT NULL DEFAULT 'Ordner',
              x REAL NOT NULL DEFAULT 0,
              y REAL NOT NULL DEFAULT 0,
              breite REAL NOT NULL DEFAULT 420,
              hoehe REAL NOT NULL DEFAULT 320,
              eingeklappt INTEGER NOT NULL DEFAULT 0,
              farbe INTEGER NOT NULL DEFAULT 0,
              farbhex TEXT,
              symbol TEXT NOT NULL DEFAULT '',
              erstellt REAL NOT NULL DEFAULT 0
            );
        """)
        db.exec("ALTER TABLE ordner ADD COLUMN farbe INTEGER NOT NULL DEFAULT 0;")
        db.exec("ALTER TABLE ordner ADD COLUMN farbhex TEXT;")
        db.exec("ALTER TABLE ordner ADD COLUMN symbol TEXT NOT NULL DEFAULT '';")
        db.exec("""
            CREATE TABLE IF NOT EXISTS notiz(
              id INTEGER PRIMARY KEY,
              board_id INTEGER NOT NULL REFERENCES board(id) ON DELETE CASCADE,
              text TEXT NOT NULL DEFAULT '',
              x REAL NOT NULL DEFAULT 0,
              y REAL NOT NULL DEFAULT 0,
              breite REAL NOT NULL DEFAULT 220,
              hoehe REAL NOT NULL DEFAULT 90,
              groesse REAL NOT NULL DEFAULT 15,
              farbe INTEGER NOT NULL DEFAULT 0,
              stil INTEGER NOT NULL DEFAULT 0,
              farbhex TEXT,
              ordner_id INTEGER,
              symbol TEXT NOT NULL DEFAULT '',
              erstellt REAL NOT NULL DEFAULT 0
            );
        """)
        db.exec("ALTER TABLE notiz ADD COLUMN stil INTEGER NOT NULL DEFAULT 0;")
        db.exec("ALTER TABLE notiz ADD COLUMN farbhex TEXT;")
        db.exec("ALTER TABLE notiz ADD COLUMN ordner_id INTEGER;")
        db.exec("ALTER TABLE notiz ADD COLUMN zettel INTEGER NOT NULL DEFAULT 0;")
        db.exec("ALTER TABLE notiz ADD COLUMN symbol TEXT NOT NULL DEFAULT '';")
        db.exec("""
            CREATE TABLE IF NOT EXISTS verbindung(
              id INTEGER PRIMARY KEY,
              board_id INTEGER NOT NULL REFERENCES board(id) ON DELETE CASCADE,
              a_art INTEGER NOT NULL, a_id INTEGER NOT NULL,
              b_art INTEGER NOT NULL, b_id INTEGER NOT NULL
            );
        """)
        db.exec("ALTER TABLE verbindung ADD COLUMN label TEXT NOT NULL DEFAULT '';")
        db.exec("""
            CREATE TABLE IF NOT EXISTS rahmen(
              id INTEGER PRIMARY KEY,
              board_id INTEGER NOT NULL REFERENCES board(id) ON DELETE CASCADE,
              name TEXT NOT NULL DEFAULT 'Bereich',
              x REAL NOT NULL DEFAULT 0,
              y REAL NOT NULL DEFAULT 0,
              breite REAL NOT NULL DEFAULT 1200,
              hoehe REAL NOT NULL DEFAULT 800,
              farbe INTEGER NOT NULL DEFAULT 1,
              reihenfolge INTEGER NOT NULL DEFAULT 0,
              erstellt REAL NOT NULL DEFAULT 0
            );
        """)
        // Volltext: FTS5 bevorzugt; wenn das System es nicht hat, einfache Tabelle.
        let hatFTS5 = db.exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS volltext USING fts5(
              name, inhalt, tokenize='unicode61 remove_diacritics 2'
            );
        """)
        if !hatFTS5 {
            db.exec("""
                CREATE TABLE IF NOT EXISTS volltext(
                  rowid INTEGER PRIMARY KEY, name TEXT, inhalt TEXT
                );
            """)
        }
        db.schreibe("INSERT OR IGNORE INTO board(id,name) VALUES(1,?)", [.text("Pinnwand")])
        // Beim Start einmalig verwaiste Volltext-Zeilen (ohne Eintrag) entfernen.
        db.exec("DELETE FROM volltext WHERE rowid NOT IN (SELECT id FROM eintrag);")
        return hatFTS5
    }

    // MARK: Einträge lesen

    func eintraege(board: Int = 1) -> [Eintrag] {
        db.lies("""
            SELECT id,pfad,name,endung,kategorie,groesse,x,y,breite,hoehe,vorschau,idml_quelle,zustand,ordner_id,kommentar,tags,lesezeichen,farbe,farbhex,symbol
            FROM eintrag WHERE board_id=? ORDER BY id
        """, [.ganz(board)]) { z in
            Eintrag(
                id: z.ganz(0), pfad: z.text(1), name: z.text(2), endung: z.text(3),
                kategorie: Kategorie(rawValue: z.text(4)) ?? .sonstiges,
                groesse: z.ganz(5), x: z.komma(6), y: z.komma(7),
                breite: z.komma(8), hoehe: z.komma(9),
                vorschau: z.textOpt(10), idmlQuelle: z.textOpt(11), zustand: z.text(12),
                ordnerID: z.ganzOpt(13), kommentar: z.text(14),
                tags: z.text(15), lesezeichen: z.textOpt(16),
                farbe: z.ganz(17), farbhex: z.textOpt(18), symbol: z.text(19)
            )
        }
    }

    // MARK: Einträge schreiben

    /// Legt eine Referenz auf eine Datei an (ohne zu kopieren) und gibt den
    /// fertigen Eintrag für die sofortige Anzeige zurück.
    func fuegeEin(url: URL, board: Int = 1, x: Double, y: Double) -> Eintrag? {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let groesse = (attrs?[.size] as? Int) ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let endung = url.pathExtension
        let kategorie = Kategorie.fuer(endung: endung)

        // Bei INDD: gleichnamige IDML daneben merken (Text kommt aus ihr).
        var idmlQuelle: String? = nil
        if kategorie == .indesign {
            let geschwister = url.deletingPathExtension().appendingPathExtension("idml")
            if fm.fileExists(atPath: geschwister.path) { idmlQuelle = geschwister.path }
        }

        let ok = db.schreibe("""
            INSERT INTO eintrag(board_id,pfad,name,endung,kategorie,groesse,datei_geaendert,erstellt,x,y,idml_quelle)
            VALUES(?,?,?,?,?,?,?,?,?,?,?)
        """, [
            .ganz(board), .text(url.path), .text(url.lastPathComponent), .text(endung),
            .text(kategorie.rawValue), .ganz(groesse), .komma(mtime),
            .komma(Date().timeIntervalSince1970), .komma(x), .komma(y),
            idmlQuelle.map { Datenbank.Wert.text($0) } ?? .leer
        ])
        guard ok else { return nil }
        let id = db.letzteID
        return Eintrag(id: id, pfad: url.path, name: url.lastPathComponent, endung: endung,
                       kategorie: kategorie, groesse: groesse, x: x, y: y,
                       breite: 190, hoehe: 210, vorschau: nil,
                       idmlQuelle: idmlQuelle, zustand: "ok", ordnerID: nil)
    }

    /// Referenz auf einen echten Finder-Ordner anlegen (zeigt später seinen Inhalt).
    func fuegeOrdnerReferenz(url: URL, board: Int = 1, x: Double, y: Double) -> Eintrag? {
        let breite = 240.0, hoehe = 268.0
        let ok = db.schreibe("""
            INSERT INTO eintrag(board_id,pfad,name,endung,kategorie,groesse,erstellt,x,y,breite,hoehe)
            VALUES(?,?,?,?,?,?,?,?,?,?,?)
        """, [
            .ganz(board), .text(url.path), .text(url.lastPathComponent), .text(""),
            .text(Kategorie.ordnerExtern.rawValue), .ganz(0),
            .komma(Date().timeIntervalSince1970), .komma(x), .komma(y), .komma(breite), .komma(hoehe)
        ])
        guard ok else { return nil }
        return Eintrag(id: db.letzteID, pfad: url.path, name: url.lastPathComponent, endung: "",
                       kategorie: .ordnerExtern, groesse: 0, x: x, y: y,
                       breite: breite, hoehe: hoehe, vorschau: nil,
                       idmlQuelle: nil, zustand: "ok", ordnerID: nil)
    }

    /// Referenz auf eine Website anlegen. `pfad` ist die vollständige URL.
    func fuegeWeblink(adresse: String, titel: String, kommentar: String = "",
                      board: Int = 1, x: Double, y: Double) -> Eintrag? {
        let breite = 212.0
        let hoehe = kommentar.isEmpty ? 86.0 : 128.0
        let ok = db.schreibe("""
            INSERT INTO eintrag(board_id,pfad,name,endung,kategorie,groesse,erstellt,x,y,breite,hoehe,kommentar)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
        """, [
            .ganz(board), .text(adresse), .text(titel), .text(""),
            .text(Kategorie.weblink.rawValue), .ganz(0),
            .komma(Date().timeIntervalSince1970), .komma(x), .komma(y), .komma(breite), .komma(hoehe),
            .text(kommentar)
        ])
        guard ok else { return nil }
        return Eintrag(id: db.letzteID, pfad: adresse, name: titel, endung: "",
                       kategorie: .weblink, groesse: 0, x: x, y: y,
                       breite: breite, hoehe: hoehe, vorschau: nil,
                       idmlQuelle: nil, zustand: "ok", ordnerID: nil, kommentar: kommentar)
    }

    /// Titel/Adresse/Kommentar eines bestehenden Weblinks ändern.
    func aktualisiereWeblink(_ id: Int, adresse: String, titel: String, kommentar: String) {
        db.schreibe("UPDATE eintrag SET pfad=?,name=?,kommentar=? WHERE id=?",
                    [.text(adresse), .text(titel), .text(kommentar), .ganz(id)])
    }

    func setzeKommentar(_ id: Int, _ kommentar: String) {
        db.schreibe("UPDATE eintrag SET kommentar=? WHERE id=?", [.text(kommentar), .ganz(id)])
    }

    func setzeTags(_ id: Int, _ tags: String) {
        db.schreibe("UPDATE eintrag SET tags=? WHERE id=?", [.text(tags), .ganz(id)])
    }

    func setzeFarbe(_ id: Int, _ farbe: Int) {
        db.schreibe("UPDATE eintrag SET farbe=? WHERE id=?", [.ganz(farbe), .ganz(id)])
    }
    func setzeFarbhex(_ id: Int, _ hex: String?) {
        db.schreibe("UPDATE eintrag SET farbhex=? WHERE id=?",
                    [hex.map { Datenbank.Wert.text($0) } ?? .leer, .ganz(id)])
    }
    func setzeSymbol(_ id: Int, _ symbol: String) {
        db.schreibe("UPDATE eintrag SET symbol=? WHERE id=?", [.text(symbol), .ganz(id)])
    }

    func setzeLesezeichen(_ id: Int, _ base64: String?) {
        db.schreibe("UPDATE eintrag SET lesezeichen=? WHERE id=?",
                    [base64.map { Datenbank.Wert.text($0) } ?? .leer, .ganz(id)])
    }

    func setzeGroesse(_ id: Int, breite: Double, hoehe: Double) {
        db.schreibe("UPDATE eintrag SET breite=?,hoehe=? WHERE id=?",
                    [.komma(breite), .komma(hoehe), .ganz(id)])
    }

    func setzeKarteOrdner(_ id: Int, ordnerID: Int?) {
        db.schreibe("UPDATE eintrag SET ordner_id=? WHERE id=?",
                    [ordnerID.map { Datenbank.Wert.ganz($0) } ?? .leer, .ganz(id)])
    }

    func setzePosition(_ id: Int, x: Double, y: Double) {
        db.schreibe("UPDATE eintrag SET x=?,y=? WHERE id=?", [.komma(x), .komma(y), .ganz(id)])
    }

    func setzeVorschau(_ id: Int, _ name: String) {
        db.schreibe("UPDATE eintrag SET vorschau=? WHERE id=?", [.text(name), .ganz(id)])
    }

    func setzeZustand(_ id: Int, _ zustand: String) {
        db.schreibe("UPDATE eintrag SET zustand=? WHERE id=?", [.text(zustand), .ganz(id)])
    }

    func aktualisierePfad(_ id: Int, pfad: String) {
        db.schreibe("UPDATE eintrag SET pfad=?,name=?,zustand='ok' WHERE id=?",
                    [.text(pfad), .text((pfad as NSString).lastPathComponent), .ganz(id)])
    }

    func entferne(_ id: Int) {
        db.inTransaktion {
            db.schreibe("DELETE FROM eintrag WHERE id=?", [.ganz(id)])
            db.schreibe("DELETE FROM volltext WHERE rowid=?", [.ganz(id)])
        }
    }

    /// Volltext einer Karte setzen (Name ist immer durchsuchbar, Inhalt optional).
    /// Der INSERT greift nur, wenn der Eintrag noch existiert – so bleibt keine
    /// verwaiste Volltext-Zeile zurück, falls die Karte zwischenzeitlich (während
    /// der Hintergrund-Indizierung) gelöscht wurde.
    func setzeInhalt(_ id: Int, name: String, inhalt: String) {
        db.inTransaktion {
            db.schreibe("DELETE FROM volltext WHERE rowid=?", [.ganz(id)])
            db.schreibe("INSERT INTO volltext(rowid,name,inhalt) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM eintrag WHERE id=?)",
                        [.ganz(id), .text(name), .text(inhalt), .ganz(id)])
            db.schreibe("UPDATE eintrag SET indiziert=1 WHERE id=?", [.ganz(id)])
        }
    }

    // MARK: Suche

    /// Liefert die IDs, die zu `text` passen. Leerer Text → nil (keine Filterung).
    func suche(_ text: String) -> Set<Int>? {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roh.isEmpty else { return nil }

        if fts5 {
            let tokens = roh
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { "\"\($0)\"*" }
            guard !tokens.isEmpty else { return nil }
            let anfrage = tokens.joined(separator: " ")
            let ids = db.lies("SELECT rowid FROM volltext WHERE volltext MATCH ?",
                              [.text(anfrage)]) { $0.ganz(0) }
            return Set(ids)
        } else {
            let muster = "%\(roh)%"
            let ids = db.lies("SELECT rowid FROM volltext WHERE name LIKE ? OR inhalt LIKE ?",
                              [.text(muster), .text(muster)]) { $0.ganz(0) }
            return Set(ids)
        }
    }

    /// Suche über ALLE Leinwände hinweg – liefert Treffer mit Leinwand-Namen
    /// (für die ⌘K-Schnellsuche). Begrenzt auf `grenze` Treffer.
    func globalSuche(_ text: String, grenze: Int = 50) -> [GlobalTreffer] {
        let roh = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !roh.isEmpty else { return [] }
        var ids: [Int] = []
        if fts5 {
            let tokens = roh
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.map { "\"\($0)\"*" }
            guard !tokens.isEmpty else { return [] }
            ids = db.lies("SELECT rowid FROM volltext WHERE volltext MATCH ? LIMIT ?",
                          [.text(tokens.joined(separator: " ")), .ganz(grenze * 4)]) { $0.ganz(0) }
        } else {
            let m = "%\(roh)%"
            ids = db.lies("SELECT rowid FROM volltext WHERE name LIKE ? OR inhalt LIKE ? LIMIT ?",
                          [.text(m), .text(m), .ganz(grenze * 4)]) { $0.ganz(0) }
        }
        guard !ids.isEmpty else { return [] }
        let liste = ids.prefix(grenze * 4).map(String.init).joined(separator: ",")
        return db.lies("""
            SELECT e.id, e.board_id, b.name, e.name, e.pfad, e.kategorie, e.tags
            FROM eintrag e JOIN board b ON b.id = e.board_id
            WHERE e.id IN (\(liste))
            ORDER BY e.board_id, e.id DESC LIMIT \(grenze)
        """) { z in
            GlobalTreffer(id: z.ganz(0), boardID: z.ganz(1), boardName: z.text(2),
                          name: z.text(3), pfad: z.text(4),
                          kategorie: Kategorie(rawValue: z.text(5)) ?? .sonstiges,
                          tags: z.text(6))
        }
    }

    // MARK: Ordner (Container)

    func ordner(board: Int = 1) -> [Ordner] {
        db.lies("""
            SELECT id,name,x,y,breite,hoehe,eingeklappt,farbe,farbhex,symbol FROM ordner
            WHERE board_id=? ORDER BY id
        """, [.ganz(board)]) { z in
            Ordner(id: z.ganz(0), name: z.text(1), x: z.komma(2), y: z.komma(3),
                   breite: z.komma(4), hoehe: z.komma(5), eingeklappt: z.ganz(6) == 1,
                   farbe: z.ganz(7), farbhex: z.textOpt(8), symbol: z.text(9))
        }
    }

    func fuegeOrdner(board: Int = 1, x: Double, y: Double) -> Ordner? {
        let ok = db.schreibe("""
            INSERT INTO ordner(board_id,name,x,y,breite,hoehe,erstellt)
            VALUES(?,?,?,?,?,?,?)
        """, [.ganz(board), .text("Mappe"), .komma(x), .komma(y),
              .komma(420), .komma(320), .komma(Date().timeIntervalSince1970)])
        guard ok else { return nil }
        return Ordner(id: db.letzteID, name: "Mappe", x: x, y: y,
                      breite: 420, hoehe: 320, eingeklappt: false, farbe: 0, farbhex: nil)
    }

    /// Einmalige Umbenennung bestehender Standard-Container „Ordner" → „Mappe".
    func benenneStandardMappen() {
        db.exec("UPDATE ordner SET name='Mappe' WHERE name='Ordner';")
    }

    func setzeOrdnerFarbe(_ id: Int, _ farbe: Int) {
        db.schreibe("UPDATE ordner SET farbe=? WHERE id=?", [.ganz(farbe), .ganz(id)])
    }
    func setzeOrdnerFarbhex(_ id: Int, _ hex: String?) {
        db.schreibe("UPDATE ordner SET farbhex=? WHERE id=?",
                    [hex.map { Datenbank.Wert.text($0) } ?? .leer, .ganz(id)])
    }
    func setzeOrdnerSymbol(_ id: Int, _ symbol: String) {
        db.schreibe("UPDATE ordner SET symbol=? WHERE id=?", [.text(symbol), .ganz(id)])
    }

    // MARK: Notizen (Textfelder)

    func notizen(board: Int = 1) -> [Notiz] {
        db.lies("""
            SELECT id,text,x,y,breite,hoehe,groesse,farbe,stil,farbhex,ordner_id,zettel,symbol FROM notiz
            WHERE board_id=? ORDER BY id
        """, [.ganz(board)]) { z in
            Notiz(id: z.ganz(0), text: z.text(1), x: z.komma(2), y: z.komma(3),
                  breite: z.komma(4), hoehe: z.komma(5), groesse: z.komma(6),
                  farbe: z.ganz(7), stil: z.ganz(8), farbhex: z.textOpt(9),
                  ordnerID: z.ganzOpt(10), zettel: z.ganz(11) == 1, symbol: z.text(12))
        }
    }

    func fuegeNotiz(board: Int = 1, x: Double, y: Double,
                    zettel: Bool = false, farbe: Int = 0) -> Notiz? {
        let breite = zettel ? 180.0 : 220.0
        let hoehe = zettel ? 150.0 : 90.0
        let ok = db.schreibe("""
            INSERT INTO notiz(board_id,text,x,y,breite,hoehe,groesse,farbe,zettel,erstellt)
            VALUES(?,?,?,?,?,?,?,?,?,?)
        """, [.ganz(board), .text(""), .komma(x), .komma(y),
              .komma(breite), .komma(hoehe), .komma(15), .ganz(farbe),
              .ganz(zettel ? 1 : 0), .komma(Date().timeIntervalSince1970)])
        guard ok else { return nil }
        return Notiz(id: db.letzteID, text: "", x: x, y: y, breite: breite, hoehe: hoehe,
                     groesse: 15, farbe: farbe, stil: 0, farbhex: nil, ordnerID: nil, zettel: zettel)
    }

    func setzeNotizOrdner(_ id: Int, ordnerID: Int?) {
        db.schreibe("UPDATE notiz SET ordner_id=? WHERE id=?",
                    [ordnerID.map { Datenbank.Wert.ganz($0) } ?? .leer, .ganz(id)])
    }

    func setzeNotizStil(_ id: Int, _ stil: Int) {
        db.schreibe("UPDATE notiz SET stil=? WHERE id=?", [.ganz(stil), .ganz(id)])
    }
    func setzeNotizFarbhex(_ id: Int, _ hex: String?) {
        db.schreibe("UPDATE notiz SET farbhex=? WHERE id=?",
                    [hex.map { Datenbank.Wert.text($0) } ?? .leer, .ganz(id)])
    }
    func setzeNotizSymbol(_ id: Int, _ symbol: String) {
        db.schreibe("UPDATE notiz SET symbol=? WHERE id=?", [.text(symbol), .ganz(id)])
    }

    func setzeNotizText(_ id: Int, _ text: String) {
        db.schreibe("UPDATE notiz SET text=? WHERE id=?", [.text(text), .ganz(id)])
    }
    func setzeNotizRahmen(_ id: Int, x: Double, y: Double, breite: Double, hoehe: Double) {
        db.schreibe("UPDATE notiz SET x=?,y=?,breite=?,hoehe=? WHERE id=?",
                    [.komma(x), .komma(y), .komma(breite), .komma(hoehe), .ganz(id)])
    }
    func setzeNotizGroesse(_ id: Int, _ groesse: Double) {
        db.schreibe("UPDATE notiz SET groesse=? WHERE id=?", [.komma(groesse), .ganz(id)])
    }
    func setzeNotizFarbe(_ id: Int, _ farbe: Int) {
        db.schreibe("UPDATE notiz SET farbe=? WHERE id=?", [.ganz(farbe), .ganz(id)])
    }
    func loescheNotiz(_ id: Int) {
        db.schreibe("DELETE FROM notiz WHERE id=?", [.ganz(id)])
    }

    // MARK: Verbindungen (Linien)

    func verbindungen(board: Int = 1) -> [Verbindung] {
        db.lies("SELECT id,a_art,a_id,b_art,b_id,label FROM verbindung WHERE board_id=? ORDER BY id",
                [.ganz(board)]) { z in
            Verbindung(id: z.ganz(0),
                       von: Auswahl(art: z.ganz(1), kennung: z.ganz(2)),
                       nach: Auswahl(art: z.ganz(3), kennung: z.ganz(4)),
                       label: z.text(5))
        }
    }

    func setzeVerbindungLabel(_ id: Int, _ label: String) {
        db.schreibe("UPDATE verbindung SET label=? WHERE id=?", [.text(label), .ganz(id)])
    }

    func fuegeVerbindung(board: Int = 1, von: Auswahl, nach: Auswahl) -> Verbindung? {
        // Doppelte (in beide Richtungen) vermeiden.
        let vorhanden = db.lies("""
            SELECT id FROM verbindung WHERE board_id=? AND
            ((a_art=? AND a_id=? AND b_art=? AND b_id=?) OR (a_art=? AND a_id=? AND b_art=? AND b_id=?))
        """, [.ganz(board),
              .ganz(von.art), .ganz(von.kennung), .ganz(nach.art), .ganz(nach.kennung),
              .ganz(nach.art), .ganz(nach.kennung), .ganz(von.art), .ganz(von.kennung)]) { $0.ganz(0) }
        if !vorhanden.isEmpty { return nil }
        let ok = db.schreibe("""
            INSERT INTO verbindung(board_id,a_art,a_id,b_art,b_id) VALUES(?,?,?,?,?)
        """, [.ganz(board), .ganz(von.art), .ganz(von.kennung), .ganz(nach.art), .ganz(nach.kennung)])
        guard ok else { return nil }
        return Verbindung(id: db.letzteID, von: von, nach: nach)
    }

    func loescheVerbindung(_ id: Int) {
        db.schreibe("DELETE FROM verbindung WHERE id=?", [.ganz(id)])
    }

    func loescheVerbindungenFuer(art: Int, id: Int) {
        db.schreibe("DELETE FROM verbindung WHERE (a_art=? AND a_id=?) OR (b_art=? AND b_id=?)",
                    [.ganz(art), .ganz(id), .ganz(art), .ganz(id)])
    }

    // MARK: Undo/Redo – Board-Inhalt id-erhaltend abgleichen

    func ersetzeInhalt(board: Int, eintraege: [Eintrag], ordner: [Ordner],
                       notizen: [Notiz], verbindungen: [Verbindung], rahmen: [Rahmen]) {
        db.inTransaktion {
            loescheFehlende("rahmen", board: board, ids: rahmen.map { $0.id })
            for r in rahmen {
                db.schreibe("INSERT OR IGNORE INTO rahmen(id,board_id,name) VALUES(?,?,?)",
                            [.ganz(r.id), .ganz(board), .text(r.name)])
                db.schreibe("UPDATE rahmen SET name=?,x=?,y=?,breite=?,hoehe=?,farbe=?,reihenfolge=? WHERE id=?",
                            [.text(r.name), .komma(r.x), .komma(r.y), .komma(r.breite), .komma(r.hoehe),
                             .ganz(r.farbe), .ganz(r.reihenfolge), .ganz(r.id)])
            }
            loescheFehlende("ordner", board: board, ids: ordner.map { $0.id })
            for o in ordner {
                db.schreibe("INSERT OR IGNORE INTO ordner(id,board_id,name) VALUES(?,?,?)",
                            [.ganz(o.id), .ganz(board), .text(o.name)])
                db.schreibe("UPDATE ordner SET name=?,x=?,y=?,breite=?,hoehe=?,eingeklappt=?,farbe=?,farbhex=?,symbol=? WHERE id=?",
                            [.text(o.name), .komma(o.x), .komma(o.y), .komma(o.breite), .komma(o.hoehe),
                             .ganz(o.eingeklappt ? 1 : 0), .ganz(o.farbe),
                             o.farbhex.map { Datenbank.Wert.text($0) } ?? .leer, .text(o.symbol), .ganz(o.id)])
            }

            loescheFehlende("eintrag", board: board, ids: eintraege.map { $0.id })
            for e in eintraege {
                db.schreibe("INSERT OR IGNORE INTO eintrag(id,board_id,pfad,name,endung,kategorie) VALUES(?,?,?,?,?,?)",
                            [.ganz(e.id), .ganz(board), .text(e.pfad), .text(e.name), .text(e.endung), .text(e.kategorie.rawValue)])
                db.schreibe("""
                    UPDATE eintrag SET pfad=?,name=?,endung=?,kategorie=?,groesse=?,x=?,y=?,breite=?,hoehe=?,vorschau=?,idml_quelle=?,zustand=?,ordner_id=?,kommentar=?,tags=?,lesezeichen=?,farbe=?,farbhex=?,symbol=? WHERE id=?
                """, [.text(e.pfad), .text(e.name), .text(e.endung), .text(e.kategorie.rawValue),
                      .ganz(e.groesse), .komma(e.x), .komma(e.y), .komma(e.breite), .komma(e.hoehe),
                      e.vorschau.map { Datenbank.Wert.text($0) } ?? .leer,
                      e.idmlQuelle.map { Datenbank.Wert.text($0) } ?? .leer,
                      .text(e.zustand),
                      e.ordnerID.map { Datenbank.Wert.ganz($0) } ?? .leer,
                      .text(e.kommentar),
                      .text(e.tags),
                      e.lesezeichen.map { Datenbank.Wert.text($0) } ?? .leer,
                      .ganz(e.farbe),
                      e.farbhex.map { Datenbank.Wert.text($0) } ?? .leer,
                      .text(e.symbol),
                      .ganz(e.id)])
            }
            db.schreibe("DELETE FROM volltext WHERE rowid NOT IN (SELECT id FROM eintrag)")

            loescheFehlende("notiz", board: board, ids: notizen.map { $0.id })
            for n in notizen {
                db.schreibe("INSERT OR IGNORE INTO notiz(id,board_id) VALUES(?,?)", [.ganz(n.id), .ganz(board)])
                db.schreibe("""
                    UPDATE notiz SET text=?,x=?,y=?,breite=?,hoehe=?,groesse=?,farbe=?,stil=?,farbhex=?,ordner_id=?,zettel=?,symbol=? WHERE id=?
                """, [.text(n.text), .komma(n.x), .komma(n.y), .komma(n.breite), .komma(n.hoehe),
                      .komma(n.groesse), .ganz(n.farbe), .ganz(n.stil),
                      n.farbhex.map { Datenbank.Wert.text($0) } ?? .leer,
                      n.ordnerID.map { Datenbank.Wert.ganz($0) } ?? .leer,
                      .ganz(n.zettel ? 1 : 0), .text(n.symbol), .ganz(n.id)])
            }

            loescheFehlende("verbindung", board: board, ids: verbindungen.map { $0.id })
            for v in verbindungen {
                db.schreibe("INSERT OR IGNORE INTO verbindung(id,board_id,a_art,a_id,b_art,b_id) VALUES(?,?,?,?,?,?)",
                            [.ganz(v.id), .ganz(board), .ganz(v.von.art), .ganz(v.von.kennung),
                             .ganz(v.nach.art), .ganz(v.nach.kennung)])
                db.schreibe("UPDATE verbindung SET label=? WHERE id=?", [.text(v.label), .ganz(v.id)])
            }
        }
    }

    private func loescheFehlende(_ tabelle: String, board: Int, ids: [Int]) {
        if ids.isEmpty {
            db.schreibe("DELETE FROM \(tabelle) WHERE board_id=?", [.ganz(board)])
        } else {
            let liste = ids.map(String.init).joined(separator: ",")
            db.exec("DELETE FROM \(tabelle) WHERE board_id=\(board) AND id NOT IN (\(liste))")
        }
    }

    func setzeOrdnerRahmen(_ id: Int, x: Double, y: Double, breite: Double, hoehe: Double) {
        db.schreibe("UPDATE ordner SET x=?,y=?,breite=?,hoehe=? WHERE id=?",
                    [.komma(x), .komma(y), .komma(breite), .komma(hoehe), .ganz(id)])
    }

    func setzeOrdnerEingeklappt(_ id: Int, _ wert: Bool) {
        db.schreibe("UPDATE ordner SET eingeklappt=? WHERE id=?",
                    [.ganz(wert ? 1 : 0), .ganz(id)])
    }

    func benenneOrdner(_ id: Int, name: String) {
        db.schreibe("UPDATE ordner SET name=? WHERE id=?", [.text(name), .ganz(id)])
    }

    func loescheOrdner(_ id: Int) {
        db.inTransaktion {
            db.schreibe("UPDATE eintrag SET ordner_id=NULL WHERE ordner_id=?", [.ganz(id)])
            db.schreibe("UPDATE notiz SET ordner_id=NULL WHERE ordner_id=?", [.ganz(id)])
            db.schreibe("DELETE FROM ordner WHERE id=?", [.ganz(id)])
        }
    }

    // MARK: Bereiche / übergeordnete Rahmen

    func rahmen(board: Int = 1) -> [Rahmen] {
        db.lies("""
            SELECT id,name,x,y,breite,hoehe,farbe,reihenfolge FROM rahmen
            WHERE board_id=? ORDER BY reihenfolge, id
        """, [.ganz(board)]) { z in
            Rahmen(id: z.ganz(0), name: z.text(1), x: z.komma(2), y: z.komma(3),
                   breite: z.komma(4), hoehe: z.komma(5), farbe: z.ganz(6), reihenfolge: z.ganz(7))
        }
    }

    func fuegeRahmen(board: Int = 1, name: String, x: Double, y: Double,
                     breite: Double, hoehe: Double, farbe: Int, reihenfolge: Int) -> Rahmen? {
        let ok = db.schreibe("""
            INSERT INTO rahmen(board_id,name,x,y,breite,hoehe,farbe,reihenfolge,erstellt)
            VALUES(?,?,?,?,?,?,?,?,?)
        """, [.ganz(board), .text(name), .komma(x), .komma(y), .komma(breite), .komma(hoehe),
              .ganz(farbe), .ganz(reihenfolge), .komma(Date().timeIntervalSince1970)])
        guard ok else { return nil }
        return Rahmen(id: db.letzteID, name: name, x: x, y: y, breite: breite, hoehe: hoehe,
                      farbe: farbe, reihenfolge: reihenfolge)
    }

    func setzeRahmenGeometrie(_ id: Int, x: Double, y: Double, breite: Double, hoehe: Double) {
        db.schreibe("UPDATE rahmen SET x=?,y=?,breite=?,hoehe=? WHERE id=?",
                    [.komma(x), .komma(y), .komma(breite), .komma(hoehe), .ganz(id)])
    }
    func benenneRahmen(_ id: Int, name: String) {
        db.schreibe("UPDATE rahmen SET name=? WHERE id=?", [.text(name), .ganz(id)])
    }
    func setzeRahmenFarbe(_ id: Int, _ farbe: Int) {
        db.schreibe("UPDATE rahmen SET farbe=? WHERE id=?", [.ganz(farbe), .ganz(id)])
    }
    func loescheRahmen(_ id: Int) {
        db.schreibe("DELETE FROM rahmen WHERE id=?", [.ganz(id)])
    }

    // MARK: Leinwände (Boards)

    func alleBoards() -> [BoardInfo] {
        db.lies("SELECT id,name FROM board ORDER BY id") {
            BoardInfo(id: $0.ganz(0), name: $0.text(1))
        }
    }

    func neuesBoard(name: String) -> Int {
        db.schreibe("INSERT INTO board(name) VALUES(?)", [.text(name)])
        return db.letzteID
    }

    func benenneBoard(_ id: Int, name: String) {
        db.schreibe("UPDATE board SET name=? WHERE id=?", [.text(name), .ganz(id)])
    }

    /// Dupliziert eine ganze Leinwand (inkl. Mappen, Karten, Notizen, Bereiche,
    /// Verbindungen, Volltext) in ein neues Board – mit sauberer ID-Neuzuordnung.
    func dupliziereBoard(_ quelle: Int, name: String) -> Int {
        var neu = 0
        var ordnerMap: [Int: Int] = [:]
        var eintragMap: [Int: Int] = [:]
        var notizMap: [Int: Int] = [:]
        let jetzt = Date().timeIntervalSince1970
        db.inTransaktion {
            db.schreibe("INSERT INTO board(name) VALUES(?)", [.text(name)])
            neu = db.letzteID
            let k = kamera(board: quelle)
            db.schreibe("UPDATE board SET zoom=?,offset_x=?,offset_y=? WHERE id=?",
                        [.komma(k.zoom), .komma(k.x), .komma(k.y), .ganz(neu)])

            for o in ordner(board: quelle) {
                db.schreibe("""
                    INSERT INTO ordner(board_id,name,x,y,breite,hoehe,eingeklappt,farbe,farbhex,symbol,erstellt)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?)
                """, [.ganz(neu), .text(o.name), .komma(o.x), .komma(o.y), .komma(o.breite), .komma(o.hoehe),
                      .ganz(o.eingeklappt ? 1 : 0), .ganz(o.farbe),
                      o.farbhex.map { Datenbank.Wert.text($0) } ?? .leer, .text(o.symbol), .komma(jetzt)])
                ordnerMap[o.id] = db.letzteID
            }

            for e in eintraege(board: quelle) {
                db.schreibe("""
                    INSERT INTO eintrag(board_id,pfad,name,endung,kategorie,groesse,erstellt,x,y,breite,hoehe,vorschau,idml_quelle,zustand,ordner_id,kommentar,tags,lesezeichen,farbe,farbhex,symbol)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [.ganz(neu), .text(e.pfad), .text(e.name), .text(e.endung), .text(e.kategorie.rawValue),
                      .ganz(e.groesse), .komma(jetzt), .komma(e.x), .komma(e.y), .komma(e.breite), .komma(e.hoehe),
                      e.vorschau.map { Datenbank.Wert.text($0) } ?? .leer,
                      e.idmlQuelle.map { Datenbank.Wert.text($0) } ?? .leer, .text(e.zustand),
                      e.ordnerID.flatMap { ordnerMap[$0] }.map { Datenbank.Wert.ganz($0) } ?? .leer,
                      .text(e.kommentar), .text(e.tags),
                      e.lesezeichen.map { Datenbank.Wert.text($0) } ?? .leer,
                      .ganz(e.farbe),
                      e.farbhex.map { Datenbank.Wert.text($0) } ?? .leer,
                      .text(e.symbol)])
                let neuId = db.letzteID
                eintragMap[e.id] = neuId
                let vt = db.lies("SELECT name,inhalt FROM volltext WHERE rowid=?", [.ganz(e.id)]) {
                    ($0.text(0), $0.text(1))
                }
                if let (nm, inh) = vt.first {
                    db.schreibe("INSERT INTO volltext(rowid,name,inhalt) VALUES(?,?,?)",
                                [.ganz(neuId), .text(nm), .text(inh)])
                }
            }

            for n in notizen(board: quelle) {
                db.schreibe("""
                    INSERT INTO notiz(board_id,text,x,y,breite,hoehe,groesse,farbe,stil,farbhex,ordner_id,zettel,symbol,erstellt)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """, [.ganz(neu), .text(n.text), .komma(n.x), .komma(n.y), .komma(n.breite), .komma(n.hoehe),
                      .komma(n.groesse), .ganz(n.farbe), .ganz(n.stil),
                      n.farbhex.map { Datenbank.Wert.text($0) } ?? .leer,
                      n.ordnerID.flatMap { ordnerMap[$0] }.map { Datenbank.Wert.ganz($0) } ?? .leer,
                      .ganz(n.zettel ? 1 : 0), .text(n.symbol), .komma(jetzt)])
                notizMap[n.id] = db.letzteID
            }

            for r in rahmen(board: quelle) {
                db.schreibe("""
                    INSERT INTO rahmen(board_id,name,x,y,breite,hoehe,farbe,reihenfolge,erstellt)
                    VALUES(?,?,?,?,?,?,?,?,?)
                """, [.ganz(neu), .text(r.name), .komma(r.x), .komma(r.y), .komma(r.breite), .komma(r.hoehe),
                      .ganz(r.farbe), .ganz(r.reihenfolge), .komma(jetzt)])
            }

            func neuID(_ art: Int, _ id: Int) -> Int? {
                switch art { case 0: return eintragMap[id]; case 1: return notizMap[id]
                             case 2: return ordnerMap[id]; default: return nil }
            }
            for v in verbindungen(board: quelle) {
                guard let a = neuID(v.von.art, v.von.kennung),
                      let b = neuID(v.nach.art, v.nach.kennung) else { continue }
                db.schreibe("INSERT INTO verbindung(board_id,a_art,a_id,b_art,b_id,label) VALUES(?,?,?,?,?,?)",
                            [.ganz(neu), .ganz(v.von.art), .ganz(a), .ganz(v.nach.art), .ganz(b), .text(v.label)])
            }
        }
        return neu
    }

    /// Löscht eine Leinwand samt Ordnern/Referenzen. Gibt die Vorschau-Dateinamen
    /// zurück, damit der Aufrufer die Thumbnails aufräumen kann. Originaldateien
    /// werden nie angefasst.
    func loescheBoard(_ id: Int) -> [String] {
        let vorschauen = db.lies("SELECT vorschau FROM eintrag WHERE board_id=? AND vorschau IS NOT NULL",
                                 [.ganz(id)]) { $0.text(0) }
        db.inTransaktion {
            let ids = db.lies("SELECT id FROM eintrag WHERE board_id=?", [.ganz(id)]) { $0.ganz(0) }
            for e in ids { db.schreibe("DELETE FROM volltext WHERE rowid=?", [.ganz(e)]) }
            db.schreibe("DELETE FROM ordner WHERE board_id=?", [.ganz(id)])
            db.schreibe("DELETE FROM rahmen WHERE board_id=?", [.ganz(id)])
            db.schreibe("DELETE FROM eintrag WHERE board_id=?", [.ganz(id)])
            db.schreibe("DELETE FROM board WHERE id=?", [.ganz(id)])
        }
        return vorschauen
    }

    /// Alle Inhalte eines Boards in EINEM Akteur-Aufruf (statt sechs) – spart die
    /// Hin-und-Rück-Sprünge beim Canvas-Wechsel.
    func ladeBoard(_ board: Int) -> BoardInhalt {
        let k = kamera(board: board)
        return BoardInhalt(
            eintraege: eintraege(board: board),
            ordner: ordner(board: board),
            notizen: notizen(board: board),
            verbindungen: verbindungen(board: board),
            rahmen: rahmen(board: board),
            zoom: k.zoom, schwenkX: k.x, schwenkY: k.y
        )
    }

    // MARK: Kamera (Schwenk/Zoom pro Board)

    func kamera(board: Int = 1) -> (zoom: Double, x: Double, y: Double) {
        db.lies("SELECT zoom,offset_x,offset_y FROM board WHERE id=?", [.ganz(board)]) {
            (zoom: $0.komma(0), x: $0.komma(1), y: $0.komma(2))
        }.first ?? (1, 0, 0)
    }

    func setzeKamera(board: Int = 1, zoom: Double, x: Double, y: Double) {
        db.schreibe("UPDATE board SET zoom=?,offset_x=?,offset_y=? WHERE id=?",
                    [.komma(zoom), .komma(x), .komma(y), .ganz(board)])
    }
}
