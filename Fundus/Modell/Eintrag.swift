import Foundation

/// Grobe Einteilung nach Dateityp – steuert Symbol, Vorschau und Indizierung.
enum Kategorie: String {
    case pdf, bild, vektor, indesign, idml, text, office, sonstiges
    case ordnerExtern   // ein echter Ordner aus dem Finder (Referenz, zeigt Inhalt)
    case weblink        // ein Link auf eine Website

    static func fuer(endung: String) -> Kategorie {
        switch endung.lowercased() {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "tiff", "tif", "heic", "heif", "heics",
             "webp", "avif", "bmp", "psd", "psb", "svg", "exr", "hdr": return .bild
        case "ai", "eps", "sketch", "afdesign", "afphoto", "afpub": return .vektor
        case "indd": return .indesign
        case "idml": return .idml
        case "txt", "md", "markdown", "csv", "tsv", "log", "json", "xml", "html", "htm",
             "rtf", "tex", "yaml", "yml", "swift", "js", "css": return .text
        case "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "key": return .office
        default: return .sonstiges
        }
    }

    /// SF-Symbol als Rückfall, wenn keine Bild-Vorschau vorliegt.
    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .bild: return "photo"
        case .vektor: return "pencil.and.outline"
        case .indesign: return "doc.append"
        case .idml: return "doc.plaintext"
        case .text: return "doc.text"
        case .office: return "doc"
        case .sonstiges: return "doc"
        case .ordnerExtern: return "folder.fill"
        case .weblink: return "globe"
        }
    }
}

/// Eine Karte auf der Pinnwand = eine Referenz auf eine Datei an ihrem Ort.
struct Eintrag: Identifiable, Equatable {
    var id: Int
    var pfad: String
    var name: String
    var endung: String
    var kategorie: Kategorie
    var groesse: Int
    var x: Double
    var y: Double
    var breite: Double
    var hoehe: Double
    var vorschau: String?        // Dateiname im Ordner .vorschau/
    var idmlQuelle: String?      // Pfad der IDML, aus der Text gezogen wurde (bei INDD)
    var zustand: String          // "ok" | "defekt"
    var ordnerID: Int?           // Mitgliedschaft in einem Ordner (nil = frei)
    var kommentar: String = ""   // freie Notiz (v. a. bei Web-Links)
    var tags: String = ""        // Schlagworte (Leer-/Komma-getrennt, durchsuchbar)
    var lesezeichen: String? = nil  // Security-Scoped Bookmark (base64) – übersteht Verschieben/Umbenennen
    var farbe: Int = 0           // Akzentfarbe (Palette-Index, v. a. Web-Links)
    var farbhex: String? = nil   // eigener Farbwert, hat Vorrang vor der Palette
    var symbol: String = ""      // SF-Symbol aus dem Katalog (leer = keins)

    var url: URL { URL(fileURLWithPath: pfad) }
    var defekt: Bool { zustand == "defekt" }
    var seitenverhaeltnis: Double { hoehe > 0 ? breite / hoehe : 1 }

    /// Einzelne Schlagworte (ohne führendes „#"), in Eingabereihenfolge, eindeutig.
    var tagListe: [String] { Eintrag.zerlegeTags(tags) }

    /// Rohe Tag-Eingabe zu einer sauberen, eindeutigen Leerzeichen-Liste normieren.
    func tagsNormalisiert(_ roh: String) -> String {
        Eintrag.zerlegeTags(roh).joined(separator: " ")
    }

    static func zerlegeTags(_ roh: String) -> [String] {
        var gesehen = Set<String>()
        var liste: [String] = []
        for teil in roh.components(separatedBy: CharacterSet(charactersIn: " ,\n\t#")) {
            let t = teil.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if gesehen.insert(t.lowercased()).inserted { liste.append(t) }
        }
        return liste
    }

    var istOrdnerRef: Bool { kategorie == .ordnerExtern }
    var istWeblink: Bool { kategorie == .weblink }
    var istDatei: Bool { kategorie != .ordnerExtern && kategorie != .weblink }
    /// Ziel-URL eines Weblinks (pfad enthält die vollständige URL-Zeichenkette).
    var webURL: URL? { istWeblink ? URL(string: pfad) : nil }
    /// Hostname eines Weblinks für die kompakte Anzeige.
    var webHost: String {
        guard let h = webURL?.host else { return pfad }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
    var groesseText: String {
        guard groesse > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(groesse), countStyle: .file)
    }
}

/// Ein Suchtreffer über ALLE Leinwände hinweg (für die ⌘K-Schnellsuche).
struct GlobalTreffer: Identifiable, Equatable {
    var id: Int            // Eintrag-ID
    var boardID: Int
    var boardName: String
    var name: String
    var pfad: String
    var kategorie: Kategorie
    var tags: String
}

/// Ergebnis des Gesundheits-Checks einer Leinwand.
struct GesundheitsBericht {
    var fehlende: [Eintrag] = []        // Datei/Ordner-Referenzen auf fehlende Ziele
    var toteLinks: [Eintrag] = []       // nicht erreichbare Web-Links
    var dubletten: [[Eintrag]] = []     // Gruppen, die denselben Pfad referenzieren
    var linksGeprueft = false           // Web-Prüfung abgeschlossen?
    var ohneLesezeichen = 0             // Datei-Karten ohne Bookmark (noch absicherbar)

    var allesInOrdnung: Bool {
        fehlende.isEmpty && toteLinks.isEmpty && dubletten.isEmpty && linksGeprueft
    }
}

/// Ein Ordner-Container auf der Leinwand: gruppiert Karten, verschiebt sie mit,
/// lässt sich ein-/ausklappen.
struct Ordner: Identifiable, Equatable {
    var id: Int
    var name: String
    var x: Double
    var y: Double
    var breite: Double
    var hoehe: Double
    var eingeklappt: Bool
    var farbe: Int
    var farbhex: String?   // eigener Farbwert, hat Vorrang vor der Palette
    var symbol: String = ""   // SF-Symbol aus dem Katalog (leer = keins)
}

/// Ein frei platzierbares Textfeld (Whiteboard-Notiz) – liegt über den Karten.
struct Notiz: Identifiable, Equatable {
    var id: Int
    var text: String
    var x: Double
    var y: Double
    var breite: Double
    var hoehe: Double
    var groesse: Double   // (reserviert, Feintuning)
    var farbe: Int
    var stil: Int         // 0 = Text, 1 = Überschrift 2, 2 = Überschrift 1
    var farbhex: String?  // eigener Farbwert, hat Vorrang vor der Palette
    var ordnerID: Int?    // Mitgliedschaft in einem Ordner (nil = frei)
    var zettel: Bool      // true = farbiger Notizzettel (Post-it) statt freier Text
    var symbol: String = ""   // SF-Symbol aus dem Katalog (leer = keins)
}

/// Eine Leinwand (mehrere möglich, als Reiter oben).
struct BoardInfo: Identifiable, Equatable {
    var id: Int
    var name: String
}

/// Ein übergeordneter Bereich/Rahmen, der UNTER den Objekten liegt und über die
/// vertikale Bereichs-Navigation gezielt angesteuert wird (wie „Seiten").
struct Rahmen: Identifiable, Equatable {
    var id: Int
    var name: String
    var x: Double
    var y: Double
    var breite: Double
    var hoehe: Double
    var farbe: Int
    var reihenfolge: Int
}

/// Eine Hilfslinie beim Andocken/Ausrichten (Smart Guide), in Leinwand-Koordinaten.
struct Hilfslinie: Equatable {
    var vertikal: Bool   // true = senkrechte Linie (X-Ausrichtung)
    var wert: Double     // X (bei vertikal) bzw. Y (bei waagerecht)
    var von: Double      // Anfang auf der jeweils anderen Achse
    var bis: Double      // Ende auf der jeweils anderen Achse
}

/// Formatierungsbefehl für den Notiz-Editor (Markdown-basiert).
enum NotizFormat: Equatable {
    case fett        // **…**
    case kursiv      // *…*
    case liste       // „- " vor die Zeile
    case checkliste  // „- [ ] " vor die Zeile
}

/// Was gerade ausgewählt ist (für Skalierung und Backspace-Löschen).
enum Auswahl: Equatable, Hashable {
    case karte(Int)
    case ordner(Int)
    case notiz(Int)

    var art: Int { switch self { case .karte: return 0; case .notiz: return 1; case .ordner: return 2 } }
    var kennung: Int { switch self { case .karte(let i), .ordner(let i), .notiz(let i): return i } }
    init(art: Int, kennung: Int) {
        switch art { case 1: self = .notiz(kennung); case 2: self = .ordner(kennung); default: self = .karte(kennung) }
    }
}

/// Eine Verbindungslinie zwischen zwei Elementen (Karte/Notiz/Ordner).
struct Verbindung: Identifiable, Equatable {
    var id: Int
    var von: Auswahl
    var nach: Auswahl
    var label: String = ""
    func betrifft(_ a: Auswahl) -> Bool { von == a || nach == a }
}

/// Alle Inhalte eines Boards – in einem Rutsch aus der Datenbank geladen.
struct BoardInhalt {
    var eintraege: [Eintrag]
    var ordner: [Ordner]
    var notizen: [Notiz]
    var verbindungen: [Verbindung]
    var rahmen: [Rahmen]
    var zoom: Double
    var schwenkX: Double
    var schwenkY: Double
}

/// Geometrie einer gebogenen Verbindung (zwei Andockpunkte + Kontrollpunkte).
struct LinienGeometrie {
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p3: CGPoint
    var mitte: CGPoint
}

/// Vollständiger Zustand eines Boards – für Undo/Redo.
struct Schnappschuss: Equatable {
    var eintraege: [Eintrag]
    var ordner: [Ordner]
    var notizen: [Notiz]
    var verbindungen: [Verbindung]
    var rahmen: [Rahmen]
}
