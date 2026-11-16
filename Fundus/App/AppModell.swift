import SwiftUI
import AppKit

/// Hält den Zustand der App zusammen: Datenbank, Leinwände (Boards), Karten,
/// Ordner-Container, Suche, Auswahl und Einstellungen. Haupt-Thread; die
/// Datenbank-Zugriffe gehen an den Akteur `Ablage`, schwere Arbeit in
/// Hintergrund-Tasks.
@MainActor
final class AppModell: ObservableObject {
    /// Für den System-Dienst „An Fundus senden" (AppDelegate reicht Objekte durch).
    static weak var shared: AppModell?

    @Published var eintraege: [Eintrag] = []
    @Published var ordnerListe: [Ordner] = []
    @Published var notizen: [Notiz] = []
    @Published var verbindungen: [Verbindung] = []
    @Published var rahmenListe: [Rahmen] = []      // übergeordnete Bereiche (hinter allem)
    @Published var aktiverRahmen: Int? = nil       // in der Bereichs-Navigation hervorgehoben
    @Published var optionAktiv = false             // ⌥ gedrückt → Bereichsrahmen verschiebbar
    @Published var spaceAktiv = false              // Leertaste gedrückt → Leinwand schwenken (statt Rahmenauswahl)
    var spaceGezogen = false                       // wurde während des Haltens geschwenkt? (unterdrückt QuickLook)
    @Published var leinwandGroesse: CGSize = .zero // sichtbare Leinwandfläche (fürs Zentrieren + Mini-Karte)
    var mausPunkt: CGPoint = .zero                 // Cursor in Leinwand-Ansichtskoordinaten (⌘+Scroll-Zoom)
    @Published var verbindenModus = false      // „Verbinden"-Werkzeug aktiv
    @Published var verbindeVon: Auswahl? = nil  // erstes gewähltes Element
    @Published var boards: [BoardInfo] = []
    @Published var aktivBoard = 1
    @Published var zielOrdner: Int? = nil   // Ordner, über dem gerade eine Karte schwebt

    @Published var suchtext = "" { didSet { sucheAnstossen() } }
    @Published var trefferIDs: Set<Int>? = nil
    @Published var symbolFilter: String? = nil   // nur Objekte mit diesem Symbol zeigen

    // ⌘K-Schnellsuche über alle Leinwände
    @Published var zeigePalette = false
    @Published var paletteText = "" { didSet { paletteSucheAnstossen() } }
    @Published var paletteTreffer: [GlobalTreffer] = []
    private var palToken = 0
    private var nachLadenZentriere: Int? = nil   // Karte, die nach Board-Wechsel zentriert wird
    @Published var auswahl: Auswahl? = nil
    @Published var markierung: Set<Auswahl> = []      // Mehrfachauswahl (Rahmen-Markierung)
    @Published var loeschKandidat: Auswahl? = nil
    @Published var loeschMehrere = false              // Backspace bei Mehrfachauswahl
    @Published var fokusNotiz: Int? = nil             // neu erstellte Notiz → sofort in Bearbeitung
    @Published var notizFormat: NotizFormat? = nil    // Formatierungsbefehl an den aktiven Notiz-Editor
    @Published var notizBearbeiten: Int? = nil        // Notiz, die in den Bearbeiten-Modus soll
    @Published var kannUndo = false
    @Published var kannRedo = false

    @Published var zeigeKuerzel = false               // Tastaturbefehl-Übersicht
    @Published var zeigeHilfe = false                 // Hilfe/Anleitung (Menü „Hilfe")
    @Published var zeigeHaftung = false               // Haftungsausschluss beim ersten Start
    @Published var zeigeReparatur = false             // Panel für defekte Verknüpfungen
    @Published var zeigeGesundheit = false            // Gesundheits-Check (Dubletten, tote Links, fehlende Dateien)
    @Published var gesundheit: GesundheitsBericht?    // Ergebnis des Checks
    @Published var gesundheitLaeuft = false
    private var linkToken = 0
    @Published var reparaturMeldung: String?          // Ergebnis eines Sammel-Relinks

    var defekteEintraege: [Eintrag] { eintraege.filter { $0.defekt } }

    // Link-Eingabe (Sheet)
    @Published var linkSheet = false
    @Published var linkEntwurfAdresse = ""
    @Published var linkEntwurfTitel = ""
    @Published var linkEntwurfKommentar = ""
    @Published var linkBearbeiteID: Int? = nil        // nil = neuer Link, sonst bestehender

    private var undoStack: [Schnappschuss] = []
    private var redoStack: [Schnappschuss] = []
    private var sammelt = false                       // unterdrückt verschachtelte Schnappschüsse

    @Published var dbOrt: URL?
    @Published var ocrAktiv: Bool
    @Published var bereit = false
    @Published var fehler: String?

    // Sicherung (externes/Netz-Laufwerk)
    @Published var backupOrt: URL?
    @Published var backupAktiv: Bool
    @Published var backupStatus: String?

    @Published var zoom: Double = 1
    @Published var schwenk: CGSize = .zero
    @Published var zeigeMiniKarte: Bool = UserDefaults.standard.object(forKey: "zeigeMiniKarte") as? Bool ?? true {
        didSet { UserDefaults.standard.set(zeigeMiniKarte, forKey: "zeigeMiniKarte") }
    }

    // MARK: Schriftgrößen (individuell einstellbar, in Einstellungen)

    /// Default aus UserDefaults lesen (0 = nicht gesetzt → Standardwert).
    private static func gelesen(_ key: String, _ std: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : std
    }
    @Published var szText: Double = AppModell.gelesen("szText", 16) {
        didSet { UserDefaults.standard.set(szText, forKey: "szText") } }
    @Published var szH1: Double = AppModell.gelesen("szH1", 34) {
        didSet { UserDefaults.standard.set(szH1, forKey: "szH1") } }
    @Published var szH2: Double = AppModell.gelesen("szH2", 24) {
        didSet { UserDefaults.standard.set(szH2, forKey: "szH2") } }
    @Published var szH3: Double = AppModell.gelesen("szH3", 19) {
        didSet { UserDefaults.standard.set(szH3, forKey: "szH3") } }
    @Published var szOrdnerTitel: Double = AppModell.gelesen("szOrdnerTitel", 12.5) {
        didSet { UserDefaults.standard.set(szOrdnerTitel, forKey: "szOrdnerTitel") } }
    @Published var szDateiname: Double = AppModell.gelesen("szDateiname", 12.5) {
        didSet { UserDefaults.standard.set(szDateiname, forKey: "szDateiname") } }
    @Published var szOrdnerInhalt: Double = AppModell.gelesen("szOrdnerInhalt", 10.5) {
        didSet { UserDefaults.standard.set(szOrdnerInhalt, forKey: "szOrdnerInhalt") } }

    /// Schriftgröße eines Notiz-Stils (0=Text, 1=H2, 2=H1, 3=H3 – historische Nummern).
    func notizGroesse(_ stil: Int) -> Double {
        switch stil { case 3: return szH3; case 2: return szH1; case 1: return szH2; default: return szText }
    }

    /// Alle Schriftgrößen auf die Standardwerte zurücksetzen.
    func schriftgroessenZuruecksetzen() {
        szText = 16; szH1 = 34; szH2 = 24; szH3 = 19
        szOrdnerTitel = 12.5; szDateiname = 12.5; szOrdnerInhalt = 10.5
    }

    enum Erscheinung: String, CaseIterable, Identifiable {
        case system, hell, dunkel
        var id: String { rawValue }
        var titel: String { self == .system ? "System" : (self == .hell ? "Hell" : "Dunkel") }
    }
    @Published var erscheinung: Erscheinung =
        Erscheinung(rawValue: UserDefaults.standard.string(forKey: "erscheinung") ?? "dunkel") ?? .dunkel {
        didSet {
            UserDefaults.standard.set(erscheinung.rawValue, forKey: "erscheinung")
            wendeErscheinungAn()
        }
    }

    /// Setzt das App-Erscheinungsbild (wirkt auf Fenster, Dialoge, Karten).
    func wendeErscheinungAn() {
        switch erscheinung {
        case .system: NSApp.appearance = nil
        case .hell: NSApp.appearance = NSAppearance(named: .aqua)
        case .dunkel: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Ist die Leinwand gerade dunkel darzustellen?
    var istDunkel: Bool {
        switch erscheinung {
        case .hell: return false
        case .dunkel: return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    /// Schnell zwischen hell und dunkel wechseln (Werkzeugleiste).
    func wechsleErscheinung() { erscheinung = istDunkel ? .hell : .dunkel }

    private var ablage: Ablage?
    private var sucheToken = 0
    /// Begrenzt gleichzeitige schwere Indizierungs-/Vorschau-Jobs (Massenimport).
    private let indexDrossel = AsyncDrossel(3)

    var vorschauOrdner: URL? { dbOrt?.appendingPathComponent(".vorschau", isDirectory: true) }
    /// Ablage für erfasste Inhalte ohne Quelldatei (eingefügte Bilder/Screenshots).
    var erfasstOrdner: URL? { dbOrt?.appendingPathComponent(".erfasst", isDirectory: true) }

    init() {
        let d = UserDefaults.standard
        ocrAktiv = d.object(forKey: "ocrAktiv") as? Bool ?? true
        backupAktiv = d.object(forKey: "backupAktiv") as? Bool ?? false
        if let pfad = d.string(forKey: "dbOrt") {
            dbOrt = URL(fileURLWithPath: pfad, isDirectory: true)
        }
        if let bp = d.string(forKey: "backupOrt") {
            backupOrt = URL(fileURLWithPath: bp, isDirectory: true)
        }
        // Haftungsausschluss nur beim allerersten Start zeigen.
        if !d.bool(forKey: "haftungBestaetigt") { zeigeHaftung = true }
        AppModell.shared = self
    }

    /// „Verstanden" im Haftungsausschluss – Hinweis künftig nicht mehr zeigen.
    func bestaetigeHaftung() {
        UserDefaults.standard.set(true, forKey: "haftungBestaetigt")
        zeigeHaftung = false
    }

    /// Standard-„Über"-Fenster mit Website + Name.
    func zeigeUeber() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Dokumente sammeln, verknüpfen und freigeben.\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: p]))
        s.append(NSAttributedString(string: "www.dwbkd.de",
            attributes: [.link: URL(string: "https://www.dwbkd.de")!,
                         .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .paragraphStyle: p]))
        s.append(NSAttributedString(string: "  ·  Daniel W. Bittner",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.labelColor, .paragraphStyle: p]))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: s])
    }

    // MARK: Duplizieren (⌥ + ziehen lässt eine Kopie am Ausgangsort zurück)

    /// Legt eine Kopie der Karte am aktuellen Ort ab (das Original wird danach
    /// weggezogen). Wird vom ⌥-Ziehen genutzt.
    func dupliziereKarteAnOrt(_ id: Int) {
        guard let ablage, let e = eintraege.first(where: { $0.id == id }) else { return }
        let board = aktivBoard
        Task {
            guard let neuId = await ablage.dupliziereEintrag(e, board: board, x: e.x, y: e.y) else { return }
            var kopie = e
            kopie.id = neuId
            eintraege.append(kopie)
        }
    }

    /// Legt eine Kopie des Textfelds/Zettels am aktuellen Ort ab (⌥-Ziehen).
    func dupliziereNotizAnOrt(_ id: Int) {
        guard let ablage, let n = notizen.first(where: { $0.id == id }) else { return }
        let board = aktivBoard
        Task {
            guard let neuId = await ablage.dupliziereNotiz(n, board: board, x: n.x, y: n.y) else { return }
            var kopie = n
            kopie.id = neuId
            notizen.append(kopie)
        }
    }

    // MARK: Datenbank öffnen / Ort wählen

    func starteFallsMoeglich() async {
        guard let ort = dbOrt, FileManager.default.fileExists(atPath: ort.path) else { return }
        await oeffne(ort: ort)
    }

    func waehleOrt(_ ort: URL) async {
        UserDefaults.standard.set(ort.path, forKey: "dbOrt")
        dbOrt = ort
        await oeffne(ort: ort)
    }

    /// Neue Sammlung: den gewählten Ordner (am Ablageort mit gewähltem Namen) erst
    /// anlegen, dann die Datenbank darin öffnen.
    func legeNeueDatenbankAn(_ ort: URL) async {
        do {
            try FileManager.default.createDirectory(at: ort, withIntermediateDirectories: true)
        } catch {
            fehler = "Ordner ließ sich nicht anlegen: \(error.localizedDescription)"
            return
        }
        await waehleOrt(ort)
    }

    private func oeffne(ort: URL) async {
        do {
            let db = ort.appendingPathComponent("Fundus.db")
            let neu = try Ablage(dbURL: db)
            ablage = neu
            if let vo = vorschauOrdner {
                try? FileManager.default.createDirectory(at: vo, withIntermediateDirectories: true)
            }
            if let eo = erfasstOrdner {
                try? FileManager.default.createDirectory(at: eo, withIntermediateDirectories: true)
            }
            // Einmalig: alte Standard-Container „Ordner" → „Mappe".
            if !UserDefaults.standard.bool(forKey: "mappeUmbenannt") {
                await neu.benenneStandardMappen()
                UserDefaults.standard.set(true, forKey: "mappeUmbenannt")
            }
            boards = await neu.alleBoards()
            aktivBoard = boards.first?.id ?? 1
            await ladeBoardInhalt()
            bereit = true
            fehler = nil
            pruefeSicherung()
        } catch {
            fehler = "Datenbank ließ sich nicht öffnen: \(error.localizedDescription)"
            bereit = false
        }
    }

    private func ladeBoardInhalt() async {
        guard let ablage else { return }
        let b = await ablage.ladeBoard(aktivBoard)
        eintraege = b.eintraege
        ordnerListe = b.ordner
        notizen = b.notizen
        verbindungen = b.verbindungen
        rahmenListe = b.rahmen
        zoom = b.zoom; schwenk = CGSize(width: b.schwenkX, height: b.schwenkY)
        auswahl = nil; markierung = []
        undoStack = []; redoStack = []; aktualisiereUndoFlags()
        pruefeVerknuepfungen()
        if let ziel = nachLadenZentriere {
            nachLadenZentriere = nil
            // Nach dem Layout zentrieren (Leinwandgröße steht evtl. erst dann).
            DispatchQueue.main.async { [weak self] in self?.zentriere(ziel) }
        }
    }

    func beende() {
        let a = ablage
        Task { await a?.checkpoint() }
    }

    /// Beim App-Beenden: aktuellen In-Memory-Stand der Leinwand autoritativ in die
    /// DB schreiben (damit keine letzte Änderung durch noch nicht ausgeführte
    /// Einzel-Writes verloren geht) und das WAL in die .db zurückschreiben.
    func sichereBeimBeenden() async {
        guard let ablage, bereit else { return }
        await ablage.ersetzeInhalt(board: aktivBoard, eintraege: eintraege, ordner: ordnerListe,
                                   notizen: notizen, verbindungen: verbindungen, rahmen: rahmenListe)
        await ablage.checkpoint()
    }

    // MARK: Sicherung (Backup)

    func waehleBackupOrt() {
        guard let u = Dateiauswahl.sicherungsOrdner() else { return }
        backupOrt = u
        UserDefaults.standard.set(u.path, forKey: "backupOrt")
        backupAktiv = true
        UserDefaults.standard.set(true, forKey: "backupAktiv")
        pruefeSicherung()
    }

    func setzeBackupAktiv(_ an: Bool) {
        backupAktiv = an
        UserDefaults.standard.set(an, forKey: "backupAktiv")
        if an { pruefeSicherung() }
    }

    var backupLetzteRegulaer: Date? { UserDefaults.standard.object(forKey: "backupLetzte2Tage") as? Date }
    var backupLetzteWoche: Date? { UserDefaults.standard.object(forKey: "backupLetzteWoche") as? Date }

    /// Prüft (bei Start/Aktivierung), ob eine Sicherung fällig ist, und führt sie aus.
    func pruefeSicherung() {
        guard backupAktiv, bereit, let ziel = backupOrt else { return }
        guard Sicherung.erreichbar(ziel) else {
            backupStatus = "Backup-Ziel nicht erreichbar (Laufwerk gemountet?)."
            return
        }
        let jetzt = Date()
        if let l = backupLetzteRegulaer { if jetzt.timeIntervalSince(l) >= 2 * 86400 { sichereJetzt(gross: false) } }
        else { sichereJetzt(gross: false) }
        if let l = backupLetzteWoche { if jetzt.timeIntervalSince(l) >= 7 * 86400 { sichereJetzt(gross: true) } }
        else { sichereJetzt(gross: true) }
    }

    /// Sofort sichern (auch für den Knopf in den Einstellungen).
    func sichereJetzt(gross: Bool) {
        guard let ziel = backupOrt, let quelle = dbOrt else {
            backupStatus = "Kein Backup-Ziel gewählt."; return
        }
        let vo = vorschauOrdner, eo = erfasstOrdner
        backupStatus = gross ? "Großes Backup läuft …" : "Backup läuft …"
        Task {
            await ablage?.checkpoint()   // WAL in die .db schreiben
            let ergebnis = await Task.detached {
                Sicherung.sichere(quelle: quelle, ziel: ziel, gross: gross, vorschau: vo, erfasst: eo)
            }.value
            if ergebnis.ok {
                UserDefaults.standard.set(Date(), forKey: gross ? "backupLetzteWoche" : "backupLetzte2Tage")
            }
            backupStatus = ergebnis.meldung
        }
    }

    // MARK: Leinwände (Boards / Reiter)

    func wechsleBoard(_ id: Int) {
        guard id != aktivBoard else { return }
        aktivBoard = id
        Task { await ladeBoardInhalt() }
    }

    func neueLeinwand() {
        guard let ablage else { return }
        Task {
            let id = await ablage.neuesBoard(name: "Leinwand \(boards.count + 1)")
            boards = await ablage.alleBoards()
            aktivBoard = id
            await ladeBoardInhalt()
        }
    }

    func dupliziereLeinwand(_ quelle: Int? = nil) {
        guard let ablage else { return }
        let q = quelle ?? aktivBoard
        let basis = boards.first(where: { $0.id == q })?.name ?? "Leinwand"
        Task {
            let id = await ablage.dupliziereBoard(q, name: "\(basis) Kopie")
            boards = await ablage.alleBoards()
            aktivBoard = id
            await ladeBoardInhalt()
        }
    }

    func benenneLeinwand(_ id: Int, _ name: String) {
        guard let ablage else { return }
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { return }
        if let i = boards.firstIndex(where: { $0.id == id }) { boards[i].name = sauber }
        Task { await ablage.benenneBoard(id, name: sauber) }
    }

    func loescheLeinwand(_ id: Int) {
        guard let ablage, boards.count > 1 else { return }
        Task {
            let vorschauen = await ablage.loescheBoard(id)
            if let vo = vorschauOrdner {
                for v in vorschauen { try? FileManager.default.removeItem(at: vo.appendingPathComponent(v)) }
            }
            boards = await ablage.alleBoards()
            if aktivBoard == id { aktivBoard = boards.first?.id ?? 1 }
            await ladeBoardInhalt()
        }
    }

    // MARK: Import (Referenz anlegen, nichts kopieren)

    func importiere(_ urls: [URL], an punkte: [CGPoint]) {
        guard let ablage else { return }
        merke()
        let ocr = ocrAktiv
        let board = aktivBoard
        for (i, url) in urls.enumerated() {
            let p = i < punkte.count ? punkte[i] : CGPoint(x: 60 + Double(i) * 24, y: 60)
            // Echte Ordner (keine Pakete wie .pages/.key/.app) werden eine Ordner-Referenz.
            let werte = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let istEchterOrdner = (werte?.isDirectory ?? false) && !(werte?.isPackage ?? false)
            Task {
                guard var e = istEchterOrdner
                        ? await ablage.fuegeOrdnerReferenz(url: url, board: board, x: p.x, y: p.y)
                        : await ablage.fuegeEin(url: url, board: board, x: p.x, y: p.y)
                else { return }
                // Direkt in einen Ordner gezogen? → Mitglied.
                if let oid = ordnerUnter(CGPoint(x: p.x + e.breite / 2, y: p.y + e.hoehe / 2)) {
                    e.ordnerID = oid
                    await ablage.setzeKarteOrdner(e.id, ordnerID: oid)
                }
                eintraege.append(e)
                anreichern(e, ocr: ocr)
                erzeugeLesezeichen(e)
            }
        }
    }

    /// Einen Website-Link als Karte anlegen (an der aktuellen Blickmitte).
    func fuegeWeblink(adresse rohAdresse: String, titel rohTitel: String, kommentar: String = "") {
        guard let ablage else { return }
        let adresse = Self.normalisiereAdresse(rohAdresse)
        guard !adresse.isEmpty else { return }
        let titel: String = {
            let t = rohTitel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            return URL(string: adresse)?.host?.replacingOccurrences(of: "www.", with: "") ?? adresse
        }()
        let komm = kommentar.trimmingCharacters(in: .whitespacesAndNewlines)
        merke()
        let board = aktivBoard
        let x = (-schwenk.width + 440) / zoom
        let y = (-schwenk.height + 240) / zoom
        Task {
            guard let e = await ablage.fuegeWeblink(adresse: adresse, titel: titel,
                                                    kommentar: komm, board: board, x: x, y: y)
            else { return }
            eintraege.append(e)
            auswahl = .karte(e.id)
            anreichern(e, ocr: false)
            holeWebMeta(e.id, adresse: adresse, autoTitel: rohTitel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// Einen fallengelassenen Web-Link (nicht aus dem Dateisystem) ablegen.
    func legeWeblinkAb(_ adresse: String, an punkt: CGPoint) {
        guard let ablage else { return }
        let sauber = Self.normalisiereAdresse(adresse)
        guard !sauber.isEmpty else { return }
        let titel = URL(string: sauber)?.host?.replacingOccurrences(of: "www.", with: "") ?? sauber
        merke()
        let board = aktivBoard
        Task {
            guard let e = await ablage.fuegeWeblink(adresse: sauber, titel: titel, board: board, x: punkt.x, y: punkt.y)
            else { return }
            eintraege.append(e)
            anreichern(e, ocr: false)
            holeWebMeta(e.id, adresse: sauber, autoTitel: true)
        }
    }

    func bearbeiteWeblink(_ id: Int, adresse rohAdresse: String, titel: String, kommentar: String) {
        guard let ablage else { return }
        let adresse = Self.normalisiereAdresse(rohAdresse)
        guard !adresse.isEmpty, let i = eintraege.firstIndex(where: { $0.id == id }) else { return }
        let komm = kommentar.trimmingCharacters(in: .whitespacesAndNewlines)
        merke()
        eintraege[i].pfad = adresse
        eintraege[i].name = titel.isEmpty ? (URL(string: adresse)?.host ?? adresse) : titel
        eintraege[i].kommentar = komm
        // Höhe anpassen, damit der Kommentar Platz hat (nur bei Standardmaßen).
        if komm.isEmpty, eintraege[i].hoehe > 86 { eintraege[i].hoehe = 86 }
        else if !komm.isEmpty, eintraege[i].hoehe < 128 { eintraege[i].hoehe = 128 }
        let e = eintraege[i]
        Task {
            await ablage.aktualisiereWeblink(id, adresse: e.pfad, titel: e.name, kommentar: e.kommentar)
            await ablage.setzeGroesse(id, breite: e.breite, hoehe: e.hoehe)
            anreichern(e, ocr: false)
            holeWebMeta(id, adresse: adresse, autoTitel: titel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Link-Sheet

    func starteLinkEingabe() {
        linkBearbeiteID = nil
        linkEntwurfAdresse = ""
        linkEntwurfTitel = ""
        linkEntwurfKommentar = ""
        linkSheet = true
    }
    func starteLinkBearbeiten(_ id: Int) {
        guard let e = eintraege.first(where: { $0.id == id }), e.istWeblink else { return }
        linkBearbeiteID = id
        linkEntwurfAdresse = e.pfad
        linkEntwurfTitel = e.name
        linkEntwurfKommentar = e.kommentar
        linkSheet = true
    }
    func bestaetigeLinkEingabe() {
        let a = linkEntwurfAdresse, t = linkEntwurfTitel, k = linkEntwurfKommentar
        if let id = linkBearbeiteID { bearbeiteWeblink(id, adresse: a, titel: t, kommentar: k) }
        else { fuegeWeblink(adresse: a, titel: t, kommentar: k) }
        linkSheet = false
    }

    static func normalisiereAdresse(_ roh: String) -> String {
        var s = roh.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if !s.contains("://") { s = "https://" + s }
        return s
    }

    /// Titel + Favicon einer Website im Hintergrund nachladen (nur vom Nutzer
    /// eingegebene Adressen). Favicon wird als Karten-Vorschau gesetzt.
    /// Vorschau (og:image, sonst Icon/Favicon) + Titel einer Website nachladen.
    func ladeLinkVorschauNeu(_ id: Int) {
        guard let e = eintraege.first(where: { $0.id == id }), e.istWeblink else { return }
        holeWebMeta(id, adresse: e.pfad, autoTitel: false)
    }

    private func holeWebMeta(_ id: Int, adresse: String, autoTitel: Bool) {
        guard let vo = vorschauOrdner else { return }
        Task.detached(priority: .utility) {
            let (titel, bildDaten, banner) = await WebErfassung.lade(adresse)
            if autoTitel, let t = titel, !t.isEmpty { await self.setzeWeblinkTitel(id, t) }
            if let data = bildDaten, let bild = NSImage(data: data),
               let tiff = bild.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                // Eindeutiger Name je nach Art – damit Icon↔Banner beim Neuladen sicher wechselt.
                // „linkbild-" = echtes Vorschaubild (og:image), „favicon-" = kleines Icon.
                let name = (banner ? "linkbild-" : "favicon-") + "\(id).png"
                try? png.write(to: vo.appendingPathComponent(name))
                let w = Double(rep.pixelsWide), h = Double(rep.pixelsHigh)
                await self.setzeLinkVorschau(id, name, banner: banner, bildB: w, bildH: h)
            }
        }
    }

    /// Vorschaubild einer Link-Karte setzen; bei einem Banner die Karte bei Bedarf
    /// höher ziehen, damit das Kopfbild Platz hat.
    private func setzeLinkVorschau(_ id: Int, _ name: String, banner: Bool, bildB: Double, bildH: Double) {
        VorschauCache.shared.verwerfe(name: name)
        guard let i = eintraege.firstIndex(where: { $0.id == id }) else { return }
        eintraege[i].vorschau = name
        Task { await ablage?.setzeVorschau(id, name) }
        if banner, bildB > 0 {
            let breite = eintraege[i].breite
            // Hochformat-Bilder nicht unbegrenzt hoch werden lassen (Seitenverhältnis deckeln).
            let bannerH = min(150.0, breite * min(bildH / bildB, 0.62))
            let textH: Double = eintraege[i].kommentar.isEmpty ? 80 : 120
            let soll = bannerH + textH
            if eintraege[i].hoehe < soll {
                eintraege[i].hoehe = soll
                let e = eintraege[i]
                Task { await ablage?.setzeGroesse(id, breite: e.breite, hoehe: e.hoehe) }
            }
        }
    }
    private func setzeWeblinkTitel(_ id: Int, _ titel: String) {
        guard let ablage, let i = eintraege.firstIndex(where: { $0.id == id }) else { return }
        eintraege[i].name = titel
        let e = eintraege[i]
        Task {
            await ablage.aktualisiereWeblink(id, adresse: e.pfad, titel: titel, kommentar: e.kommentar)
            anreichern(e, ocr: false)
        }
    }
    private func setzeFavicon(_ id: Int, _ name: String) {
        VorschauCache.shared.verwerfe(name: name)
        if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].vorschau = name }
        Task { await ablage?.setzeVorschau(id, name) }
    }

    // MARK: Pfad teilen (macOS / Windows)

    /// Kopiert den Dateipfad einer Karte – wahlweise mit „/" (macOS/Unix) oder „\"
    /// (Windows), damit er auf dem jeweils anderen System per Hand nutzbar ist.
    func kopierePfad(_ e: Eintrag, windows: Bool) {
        let pfad = windows ? e.pfad.replacingOccurrences(of: "/", with: "\\") : e.pfad
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pfad, forType: .string)
    }

    // MARK: Verknüpfungen reparieren

    /// Wählt einen Ordner und sucht darin (rekursiv) nach gleichnamigen Dateien
    /// für alle defekten Karten – und verknüpft sie neu.
    func waehleReparaturOrdner() {
        guard let u = Dateiauswahl.reparaturOrdner() else { return }
        repariereAlle(inOrdner: u)
    }

    func repariereAlle(inOrdner root: URL) {
        let defekte = eintraege.filter { $0.defekt && $0.istDatei }
        guard !defekte.isEmpty else { reparaturMeldung = "Keine defekten Dateien."; return }
        let gesuchte = Dictionary(grouping: defekte, by: { ($0.name as NSString).lastPathComponent })
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var treffer: [Int: URL] = [:]
            if let laeufer = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                           options: [.skipsHiddenFiles]) {
                for fall in laeufer {
                    guard let u = fall as? URL else { continue }
                    if let kandidaten = gesuchte[u.lastPathComponent] {
                        for k in kandidaten where treffer[k.id] == nil { treffer[k.id] = u }
                    }
                }
            }
            await self.wendeReparaturAn(treffer, gesamt: defekte.count)
        }
    }

    private func wendeReparaturAn(_ treffer: [Int: URL], gesamt: Int) {
        for (id, url) in treffer {
            if let e = eintraege.first(where: { $0.id == id }) { neuVerknuepfe(e, mit: url) }
        }
        reparaturMeldung = "\(treffer.count) von \(gesamt) wieder verknüpft."
    }

    // MARK: Erfassen (Zwischenablage / Drop)

    /// Leinwandpunkt unter dem Mauszeiger (oder Bildschirmmitte) für neue Objekte.
    private func erfassungsPunkt() -> CGPoint {
        let p = mausPunkt == .zero
            ? CGPoint(x: leinwandGroesse.width / 2, y: leinwandGroesse.height / 2)
            : mausPunkt
        return CGPoint(x: (p.x - schwenk.width) / zoom, y: (p.y - schwenk.height) / zoom)
    }

    /// ⌘V: Inhalt der Zwischenablage als passendes Objekt ablegen.
    func fuegeAusZwischenablage() {
        verarbeitePasteboard(NSPasteboard.general, an: erfassungsPunkt())
    }

    /// Inhalt eines Pasteboards (Zwischenablage ODER Dienst „An Fundus senden")
    /// als passende Objekte auf der Leinwand ablegen.
    @discardableResult
    func verarbeitePasteboard(_ pb: NSPasteboard, an ziel: CGPoint) -> Bool {
        // 1) Datei(en) → Referenz(en)
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let punkte = urls.enumerated().map { (i, _) in
                CGPoint(x: ziel.x + Double(i) * 26, y: ziel.y + Double(i) * 26)
            }
            importiere(urls, an: punkte)
            return true
        }
        // 2) Bild / Screenshot → Datei in .erfasst/ + Karte
        if let bild = NSImage(pasteboard: pb) {
            speichereBildAlsKarte(bild, an: ziel)
            return true
        }
        // 3) Web-URL → Link
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
           let u = urls.first, !u.isFileURL {
            legeWeblinkAb(u.absoluteString, an: ziel)
            return true
        }
        // 4) Text → Link (wenn URL) oder Notiz
        if let s = pb.string(forType: .string) {
            let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            if let u = URL(string: text), (u.scheme == "http" || u.scheme == "https"), u.host != nil {
                legeWeblinkAb(text, an: ziel)
            } else {
                erstelleNotizMitText(text, an: ziel)
            }
            return true
        }
        return false
    }

    /// Eingang vom System-Dienst „An Fundus senden" – in die Mitte der sichtbaren
    /// Leinwand legen und darauf aufmerksam machen.
    func empfangeVonDienst(_ pb: NSPasteboard) {
        guard bereit else { return }
        let mitte = CGPoint(x: (leinwandGroesse.width / 2 - schwenk.width) / zoom,
                            y: (leinwandGroesse.height / 2 - schwenk.height) / zoom)
        if verarbeitePasteboard(pb, an: mitte) {
            exportMeldung = "An Fundus gesendet."
        }
    }

    /// Ein Bild (z. B. Screenshot) als PNG in .erfasst/ sichern und als Karte anlegen.
    func speichereBildAlsKarte(_ bild: NSImage, an punkt: CGPoint) {
        guard let eo = erfasstOrdner,
              let tiff = bild.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: eo, withIntermediateDirectories: true)
        let name = "erfasst-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        let url = eo.appendingPathComponent(name)
        guard (try? png.write(to: url)) != nil else { return }
        importiere([url], an: [punkt])
    }

    /// Text als Notiz anlegen (für Drop/Paste).
    func erstelleNotizMitText(_ text: String, an punkt: CGPoint) {
        guard let ablage else { return }
        merke()
        let board = aktivBoard
        // Höhe grob an die Textmenge anpassen.
        let zeilen = max(1, text.count / 34 + text.filter { $0 == "\n" }.count + 1)
        let hoehe = min(360, max(90, Double(zeilen) * 22 + 24))
        Task {
            guard var n = await ablage.fuegeNotiz(board: board, x: punkt.x, y: punkt.y) else { return }
            n.text = text
            n.hoehe = hoehe
            notizen.append(n)
            auswahl = .notiz(n.id)
            await ablage.setzeNotizText(n.id, text)
            await ablage.setzeNotizRahmen(n.id, x: n.x, y: n.y, breite: n.breite, hoehe: n.hoehe)
        }
    }

    private func anreichern(_ e: Eintrag, ocr: Bool) {
        guard let ablage else { return }
        let tagText = e.tags.isEmpty ? "" : e.tags + "\n"
        // Weblink: Titel + Adresse + Kommentar durchsuchbar machen (kein Dateizugriff).
        if e.kategorie == .weblink {
            let text = "\(tagText)\(e.name)\n\(e.pfad)\n\(e.kommentar)"
            Task.detached(priority: .utility) { await ablage.setzeInhalt(e.id, name: e.name, inhalt: text) }
            return
        }
        // Externer Ordner: Dateinamen rekursiv indexieren (Suche findet ihn über den Inhalt).
        if e.kategorie == .ordnerExtern {
            Task.detached(priority: .utility) {
                await self.indexDrossel.mit {
                    let text = tagText + OrdnerInhalt.indexText(e.url)
                    await ablage.setzeInhalt(e.id, name: e.name, inhalt: text)
                }
            }
            return
        }
        guard let vo = vorschauOrdner else { return }
        Task.detached(priority: .utility) {
            await self.indexDrossel.mit {
                if let name = await Vorschau.erzeuge(fuer: e.url, id: e.id, ordner: vo) {
                    await ablage.setzeVorschau(e.id, name)
                    await self.setzeVorschauLokal(e.id, name)
                }
                let text = tagText + Textextraktion.text(fuer: e.url, kategorie: e.kategorie,
                                                         idmlQuelle: e.idmlQuelle, ocr: ocr)
                await ablage.setzeInhalt(e.id, name: e.name, inhalt: text)
            }
        }
    }

    private func setzeVorschauLokal(_ id: Int, _ name: String) {
        VorschauCache.shared.verwerfe(name: name)   // falls gleicher Name neu geschrieben
        if let idx = eintraege.firstIndex(where: { $0.id == id }) { eintraege[idx].vorschau = name }
    }

    // MARK: Karten bewegen / skalieren

    func verschiebe(_ id: Int, x: Double, y: Double) {
        guard let idx = eintraege.firstIndex(where: { $0.id == id }) else { return }
        eintraege[idx].x = x
        eintraege[idx].y = y
    }

    /// Während des Ziehens: welchen Ordner würde die Karte treffen? (Highlight)
    func aktualisiereZiel(_ mitte: CGPoint) {
        zielOrdner = ordnerUnter(mitte)
    }

    /// Nach dem Bewegen: Position sichern und Ordner-Mitgliedschaft neu bestimmen.
    func sichereKarte(_ id: Int) {
        zielOrdner = nil
        guard let ablage, let e = eintraege.first(where: { $0.id == id }) else { return }
        let mitte = CGPoint(x: e.x + e.breite / 2, y: e.y + e.hoehe / 2)
        let neuerOrdner = ordnerUnter(mitte)
        if neuerOrdner != e.ordnerID, let idx = eintraege.firstIndex(where: { $0.id == id }) {
            eintraege[idx].ordnerID = neuerOrdner
        }
        Task {
            await ablage.setzePosition(id, x: e.x, y: e.y)
            await ablage.setzeKarteOrdner(id, ordnerID: neuerOrdner)
        }
    }

    func skaliere(_ id: Int, breite: Double, hoehe: Double) {
        guard let idx = eintraege.firstIndex(where: { $0.id == id }) else { return }
        eintraege[idx].breite = breite
        eintraege[idx].hoehe = hoehe
    }

    // Vollständige Rahmen (x/y/Breite/Höhe) – fürs Skalieren über alle vier Ecken.
    func formeKarte(_ id: Int, _ r: CGRect) {
        guard let i = eintraege.firstIndex(where: { $0.id == id }) else { return }
        eintraege[i].x = r.minX; eintraege[i].y = r.minY
        eintraege[i].breite = r.width; eintraege[i].hoehe = r.height
    }
    func sichereKarteRahmen(_ id: Int) {
        guard let ablage, let e = eintraege.first(where: { $0.id == id }) else { return }
        Task {
            await ablage.setzePosition(id, x: e.x, y: e.y)
            await ablage.setzeGroesse(id, breite: e.breite, hoehe: e.hoehe)
        }
    }
    func formeNotiz(_ id: Int, _ r: CGRect) {
        guard let i = notizen.firstIndex(where: { $0.id == id }) else { return }
        notizen[i].x = r.minX; notizen[i].y = r.minY
        notizen[i].breite = r.width; notizen[i].hoehe = r.height
    }
    func formeRahmenObjekt(_ id: Int, _ r: CGRect) {
        guard let i = rahmenListe.firstIndex(where: { $0.id == id }) else { return }
        rahmenListe[i].x = r.minX; rahmenListe[i].y = r.minY
        rahmenListe[i].breite = r.width; rahmenListe[i].hoehe = r.height
    }
    func formeOrdner(_ id: Int, _ r: CGRect) {
        guard let i = ordnerListe.firstIndex(where: { $0.id == id }) else { return }
        ordnerListe[i].x = r.minX; ordnerListe[i].y = r.minY
        ordnerListe[i].breite = r.width; ordnerListe[i].hoehe = r.height
    }

    func sichereGroesse(_ id: Int) {
        guard let ablage, let e = eintraege.first(where: { $0.id == id }) else { return }
        Task { await ablage.setzeGroesse(id, breite: e.breite, hoehe: e.hoehe) }
    }

    // MARK: Ordner-Container

    func neuerOrdner() {
        guard let ablage else { return }
        merke()
        // Etwa in die Mitte des sichtbaren Ausschnitts legen.
        let x = (-schwenk.width + 420) / zoom
        let y = (-schwenk.height + 220) / zoom
        Task {
            if let o = await ablage.fuegeOrdner(board: aktivBoard, x: x, y: y) {
                ordnerListe.append(o)
                auswahl = .ordner(o.id)
            }
        }
    }

    func verschiebeOrdner(_ id: Int, dx: Double, dy: Double) {
        guard let oi = ordnerListe.firstIndex(where: { $0.id == id }) else { return }
        ordnerListe[oi].x += dx
        ordnerListe[oi].y += dy
        for i in eintraege.indices where eintraege[i].ordnerID == id {
            eintraege[i].x += dx
            eintraege[i].y += dy
        }
        for i in notizen.indices where notizen[i].ordnerID == id {
            notizen[i].x += dx
            notizen[i].y += dy
        }
    }

    func sichereOrdner(_ id: Int) {
        guard let ablage, let o = ordnerListe.first(where: { $0.id == id }) else { return }
        let mitglieder = eintraege.filter { $0.ordnerID == id }
        let notizMitglieder = notizen.filter { $0.ordnerID == id }
        Task {
            await ablage.setzeOrdnerRahmen(id, x: o.x, y: o.y, breite: o.breite, hoehe: o.hoehe)
            for m in mitglieder { await ablage.setzePosition(m.id, x: m.x, y: m.y) }
            for n in notizMitglieder { await ablage.setzeNotizRahmen(n.id, x: n.x, y: n.y, breite: n.breite, hoehe: n.hoehe) }
        }
    }

    func skaliereOrdner(_ id: Int, breite: Double, hoehe: Double) {
        guard let oi = ordnerListe.firstIndex(where: { $0.id == id }) else { return }
        ordnerListe[oi].breite = breite
        ordnerListe[oi].hoehe = hoehe
    }

    func klappeOrdner(_ id: Int) {
        guard let ablage, let oi = ordnerListe.firstIndex(where: { $0.id == id }) else { return }
        merke()
        ordnerListe[oi].eingeklappt.toggle()
        let wert = ordnerListe[oi].eingeklappt
        Task { await ablage.setzeOrdnerEingeklappt(id, wert) }
    }

    func benenneOrdner(_ id: Int, _ name: String) {
        guard let ablage else { return }
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { return }
        if let oi = ordnerListe.firstIndex(where: { $0.id == id }) { ordnerListe[oi].name = sauber }
        Task { await ablage.benenneOrdner(id, name: sauber) }
    }

    /// Kontextmenü: ohne Rückfrage. Löst nur die Gruppierung, Karten bleiben.
    func loescheOrdner(_ id: Int) {
        guard let ablage else { return }
        merke()
        entferneVerbindungenFuer(.ordner(id))
        ordnerListe.removeAll { $0.id == id }
        for i in eintraege.indices where eintraege[i].ordnerID == id { eintraege[i].ordnerID = nil }
        for i in notizen.indices where notizen[i].ordnerID == id { notizen[i].ordnerID = nil }
        if auswahl == .ordner(id) { auswahl = nil }
        Task { await ablage.loescheOrdner(id) }
    }

    func mitgliederZahl(_ id: Int) -> Int { eintraege.filter { $0.ordnerID == id }.count }

    func setzeOrdnerFarbe(_ id: Int, _ farbe: Int) {
        guard let ablage else { return }
        merke()
        if let oi = ordnerListe.firstIndex(where: { $0.id == id }) { ordnerListe[oi].farbe = farbe }
        Task { await ablage.setzeOrdnerFarbe(id, farbe) }
    }
    func setzeOrdnerFarbhex(_ id: Int, _ hex: String?) {
        guard let ablage else { return }
        merke()
        if let oi = ordnerListe.firstIndex(where: { $0.id == id }) { ordnerListe[oi].farbhex = hex }
        Task { await ablage.setzeOrdnerFarbhex(id, hex) }
    }

    // MARK: Notizen (Textfelder)

    func neueNotiz() {
        guard let ablage else { return }
        merke()
        let x = (-schwenk.width + 420) / zoom
        let y = (-schwenk.height + 220) / zoom
        Task {
            if let n = await ablage.fuegeNotiz(board: aktivBoard, x: x, y: y) {
                notizen.append(n)
                auswahl = .notiz(n.id)
                fokusNotiz = n.id   // Cursor springt direkt in den neuen Rahmen
            }
        }
    }

    /// Farbiger Notizzettel (Post-it) – startet sofort im Bearbeitungsmodus.
    func neuerZettel() {
        guard let ablage else { return }
        merke()
        let x = (-schwenk.width + 440) / zoom
        let y = (-schwenk.height + 240) / zoom
        // Farbe für etwas Abwechslung durchrotieren.
        let farbe = notizen.filter { $0.zettel }.count % Design.objektFarben.count
        Task {
            if let n = await ablage.fuegeNotiz(board: aktivBoard, x: x, y: y, zettel: true, farbe: farbe) {
                notizen.append(n)
                auswahl = .notiz(n.id)
                fokusNotiz = n.id
            }
        }
    }

    func verschiebeNotiz(_ id: Int, x: Double, y: Double) {
        guard let i = notizen.firstIndex(where: { $0.id == id }) else { return }
        notizen[i].x = x; notizen[i].y = y
    }
    func skaliereNotiz(_ id: Int, breite: Double, hoehe: Double) {
        guard let i = notizen.firstIndex(where: { $0.id == id }) else { return }
        notizen[i].breite = breite; notizen[i].hoehe = hoehe
    }
    func sichereNotizRahmen(_ id: Int) {
        zielOrdner = nil
        guard let ablage, let n = notizen.first(where: { $0.id == id }) else { return }
        let mitte = CGPoint(x: n.x + n.breite / 2, y: n.y + n.hoehe / 2)
        let neuerOrdner = ordnerUnter(mitte)
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].ordnerID = neuerOrdner }
        Task {
            await ablage.setzeNotizRahmen(id, x: n.x, y: n.y, breite: n.breite, hoehe: n.hoehe)
            await ablage.setzeNotizOrdner(id, ordnerID: neuerOrdner)
        }
    }

    /// Notiz in einem eingeklappten Ordner? → ausblenden.
    func istVerborgenN(_ n: Notiz) -> Bool {
        guard let oid = n.ordnerID else { return false }
        return ordnerListe.first(where: { $0.id == oid })?.eingeklappt ?? false
    }
    func setzeNotizText(_ id: Int, _ text: String) {
        guard let ablage else { return }
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].text = text }
        Task { await ablage.setzeNotizText(id, text) }
    }

    /// Ein einzelnes Element aus einem referenzierten Finder-Ordner öffnen
    /// (`reveal`=false) oder im Finder zeigen/auswählen (`reveal`=true).
    func oeffneOrdnerKind(_ e: Eintrag, _ kind: OrdnerInhalt.Eintrag, reveal: Bool) {
        guard e.istOrdnerRef else { return }
        let url = e.url.appendingPathComponent(kind.name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            exportMeldung = "„\(kind.name)“ wurde nicht gefunden (verschoben?)."
            return
        }
        if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(url) }
    }

    /// Formatierungsbefehl auslösen: die gewählte Notiz in den Bearbeiten-Modus
    /// bringen (falls nötig) und den Befehl an ihren Editor reichen.
    func formatiereNotiz(_ f: NotizFormat) {
        guard case let .notiz(id)? = auswahl else { return }
        notizBearbeiten = id
        notizFormat = f
    }

    /// Checklisten-Zeile (per Antippen) ab-/anhaken – schreibt `- [ ]` ⇄ `- [x]`.
    func toggleNotizCheckliste(_ id: Int, zeile index: Int) {
        guard let i = notizen.firstIndex(where: { $0.id == id }) else { return }
        var zeilen = notizen[i].text.components(separatedBy: "\n")
        guard index >= 0, index < zeilen.count else { return }
        let z = zeilen[index]
        if let r = z.range(of: #"^(\s*)-\s\[( |x|X)\]\s"#, options: .regularExpression) {
            let marke = z[r]
            if marke.contains("[ ]") {
                zeilen[index] = z.replacingCharacters(in: r, with: marke.replacingOccurrences(of: "[ ]", with: "[x]"))
            } else {
                zeilen[index] = z.replacingCharacters(in: r,
                    with: marke.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]"))
            }
            let neu = zeilen.joined(separator: "\n")
            merke()
            notizen[i].text = neu
            Task { await ablage?.setzeNotizText(id, neu) }
        }
    }
    func setzeNotizGroesse(_ id: Int, _ groesse: Double) {
        guard let ablage else { return }
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].groesse = groesse }
        Task { await ablage.setzeNotizGroesse(id, groesse) }
    }
    func setzeNotizFarbe(_ id: Int, _ farbe: Int) {
        guard let ablage else { return }
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].farbe = farbe }
        Task { await ablage.setzeNotizFarbe(id, farbe) }
    }
    func setzeNotizStil(_ id: Int, _ stil: Int) {
        guard let ablage, let i = notizen.firstIndex(where: { $0.id == id }) else { return }
        merke()
        notizen[i].stil = stil
        // Höhe/Breite mitwachsen lassen, damit die Überschrift nicht abschneidet.
        // (stil: 0=Text, 1=H2, 2=H1, 3=H3)
        let minH: Double = stil == 2 ? 70 : (stil == 1 ? 54 : (stil == 3 ? 46 : 0))
        let minB: Double = stil == 2 ? 240 : (stil == 1 ? 200 : (stil == 3 ? 180 : 0))
        var rahmenGeaendert = false
        if notizen[i].hoehe < minH { notizen[i].hoehe = minH; rahmenGeaendert = true }
        if notizen[i].breite < minB { notizen[i].breite = minB; rahmenGeaendert = true }
        let n = notizen[i]
        Task {
            await ablage.setzeNotizStil(id, stil)
            if rahmenGeaendert {
                await ablage.setzeNotizRahmen(id, x: n.x, y: n.y, breite: n.breite, hoehe: n.hoehe)
            }
        }
    }
    func setzeNotizFarbhex(_ id: Int, _ hex: String?) {
        guard let ablage else { return }
        merke()
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].farbhex = hex }
        Task { await ablage.setzeNotizFarbhex(id, hex) }
    }
    func loescheNotiz(_ id: Int) {
        guard let ablage else { return }
        merke()
        entferneVerbindungenFuer(.notiz(id))
        notizen.removeAll { $0.id == id }
        if auswahl == .notiz(id) { auswahl = nil }
        Task { await ablage.loescheNotiz(id) }
    }

    private func ordnerUnter(_ punkt: CGPoint) -> Int? {
        for o in ordnerListe.reversed() where !o.eingeklappt {
            let r = CGRect(x: o.x, y: o.y, width: o.breite, height: o.hoehe)
            if r.contains(punkt) { return o.id }
        }
        return nil
    }

    func istVerborgen(_ e: Eintrag) -> Bool {
        guard let oid = e.ordnerID else { return false }
        return ordnerListe.first(where: { $0.id == oid })?.eingeklappt ?? false
    }

    // MARK: Undo / Redo

    private func aktuell() -> Schnappschuss {
        Schnappschuss(eintraege: eintraege, ordner: ordnerListe, notizen: notizen,
                      verbindungen: verbindungen, rahmen: rahmenListe)
    }

    /// Vor einer Änderung aufrufen (Zustand sichern).
    func merke() {
        guard !sammelt, bereit else { return }
        let s = aktuell()
        if undoStack.last == s { return }
        undoStack.append(s)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
        aktualisiereUndoFlags()
    }

    /// Beginn eines Drags/Resizes – ein Schnappschuss pro Geste.
    func beginneAktion() { merke() }

    /// Mehrere Teilaktionen zu einem Undo-Schritt bündeln.
    func gebuendelt(_ arbeit: () -> Void) {
        merke()
        sammelt = true
        arbeit()
        sammelt = false
    }

    func rueckgaengig() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(aktuell())
        wendeAn(s)
        aktualisiereUndoFlags()
    }
    func wiederherstellen() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(aktuell())
        wendeAn(s)
        aktualisiereUndoFlags()
    }

    private func wendeAn(_ s: Schnappschuss) {
        let vorher = Set(eintraege.map { $0.id })
        eintraege = s.eintraege
        ordnerListe = s.ordner
        notizen = s.notizen
        verbindungen = s.verbindungen
        rahmenListe = s.rahmen
        auswahl = nil
        markierung = []
        let board = aktivBoard
        Task { await ablage?.ersetzeInhalt(board: board, eintraege: s.eintraege,
                                           ordner: s.ordner, notizen: s.notizen,
                                           verbindungen: s.verbindungen, rahmen: s.rahmen) }
        let neu = Set(s.eintraege.map { $0.id }).subtracting(vorher)
        for id in neu { neuIndiziere(id) }
    }

    private func aktualisiereUndoFlags() {
        kannUndo = !undoStack.isEmpty
        kannRedo = !redoStack.isEmpty
    }

    // MARK: Auswahl / Mehrfachauswahl

    func einzelAuswahl(_ a: Auswahl) {
        auswahl = a
        markierung = [a]
    }
    func leereAuswahl() {
        auswahl = nil
        markierung = []
    }
    func istMarkiert(_ a: Auswahl) -> Bool { auswahl == a || markierung.contains(a) }

    /// Rahmen-Markierung: alle Objekte im Rechteck (Leinwand-Koordinaten) wählen.
    func markiereBereich(_ rect: CGRect) {
        var treffer: Set<Auswahl> = []
        for e in eintraege where !istVerborgen(e) {
            if rect.intersects(CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)) { treffer.insert(.karte(e.id)) }
        }
        for n in notizen {
            if rect.intersects(CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe)) { treffer.insert(.notiz(n.id)) }
        }
        for o in ordnerListe {
            let h = o.eingeklappt ? 46.0 : o.hoehe
            if rect.intersects(CGRect(x: o.x, y: o.y, width: o.breite, height: h)) { treffer.insert(.ordner(o.id)) }
        }
        markierung = treffer
        auswahl = treffer.count == 1 ? treffer.first : nil
    }

    func verschiebeMarkierung(dx: Double, dy: Double) {
        for a in markierung {
            switch a {
            case .karte(let id):
                if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].x += dx; eintraege[i].y += dy }
            case .notiz(let id):
                if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].x += dx; notizen[i].y += dy }
            case .ordner(let id):
                if let i = ordnerListe.firstIndex(where: { $0.id == id }) {
                    ordnerListe[i].x += dx; ordnerListe[i].y += dy
                    for j in eintraege.indices where eintraege[j].ordnerID == id
                        && !markierung.contains(.karte(eintraege[j].id)) {
                        eintraege[j].x += dx; eintraege[j].y += dy
                    }
                    for j in notizen.indices where notizen[j].ordnerID == id
                        && !markierung.contains(.notiz(notizen[j].id)) {
                        notizen[j].x += dx; notizen[j].y += dy
                    }
                }
            }
        }
    }

    func sichereMarkierung() {
        for a in markierung {
            switch a {
            case .karte(let id): sichereKarte(id)
            case .notiz(let id): sichereNotizRahmen(id)
            case .ordner(let id): sichereOrdner(id)
            }
        }
    }

    func entferneMarkierung() {
        gebuendelt {
            for a in markierung {
                switch a {
                case .karte(let id): if let e = eintraege.first(where: { $0.id == id }) { entferne(e) }
                case .notiz(let id): loescheNotiz(id)
                case .ordner(let id): loescheOrdner(id)
                }
            }
        }
        markierung = []
        auswahl = nil
        loeschMehrere = false
    }

    // MARK: Ordnen (Ausrichten / Verteilen / Raster / in Mappe)

    enum Ausrichtung { case links, rechts, oben, unten, mitteH, mitteV }

    /// Rechtecke der aktuell markierten Objekte (Leinwand-Koordinaten).
    private func markierteRechtecke() -> [(a: Auswahl, r: CGRect)] {
        markierung.compactMap { a in rechteck(a).map { (a, $0) } }
    }

    /// Objekt absolut positionieren (Ordner nimmt seine Mitglieder mit).
    private func setzePosAbsolut(_ a: Auswahl, x: Double, y: Double) {
        switch a {
        case .karte(let id): verschiebe(id, x: x, y: y)
        case .notiz(let id): verschiebeNotiz(id, x: x, y: y)
        case .ordner(let id):
            if let o = ordnerListe.first(where: { $0.id == id }) {
                verschiebeOrdner(id, dx: x - o.x, dy: y - o.y)
            }
        }
    }

    /// Nur die Position eines markierten Objekts sichern (ohne Mitgliedschafts-
    /// Neuberechnung – fürs Ausrichten/Verteilen, das nichts einsortieren soll).
    private func persistierePosition(_ a: Auswahl) {
        guard let ablage else { return }
        switch a {
        case .karte(let id):
            if let e = eintraege.first(where: { $0.id == id }) {
                Task { await ablage.setzePosition(id, x: e.x, y: e.y) }
            }
        case .notiz(let id):
            if let n = notizen.first(where: { $0.id == id }) {
                Task { await ablage.setzeNotizRahmen(id, x: n.x, y: n.y, breite: n.breite, hoehe: n.hoehe) }
            }
        case .ordner(let id): sichereOrdner(id)
        }
    }

    private func sichereMarkiertePositionen() { for a in markierung { persistierePosition(a) } }

    func richteAus(_ art: Ausrichtung) {
        let stücke = markierteRechtecke()
        guard stücke.count > 1 else { return }
        let union = stücke.dropFirst().reduce(stücke[0].r) { $0.union($1.r) }
        gebuendelt {
            for (a, r) in stücke {
                switch art {
                case .links:  setzePosAbsolut(a, x: union.minX, y: r.minY)
                case .rechts: setzePosAbsolut(a, x: union.maxX - r.width, y: r.minY)
                case .oben:   setzePosAbsolut(a, x: r.minX, y: union.minY)
                case .unten:  setzePosAbsolut(a, x: r.minX, y: union.maxY - r.height)
                case .mitteH: setzePosAbsolut(a, x: union.midX - r.width / 2, y: r.minY)
                case .mitteV: setzePosAbsolut(a, x: r.minX, y: union.midY - r.height / 2)
                }
            }
        }
        sichereMarkiertePositionen()
    }

    /// Objekte gleichmäßig verteilen (Abstände der Mittelpunkte zwischen erstem
    /// und letztem angleichen).
    func verteile(waagerecht: Bool) {
        let stücke = markierteRechtecke()
        guard stücke.count > 2 else { return }
        let sortiert = stücke.sorted { waagerecht ? $0.r.midX < $1.r.midX : $0.r.midY < $1.r.midY }
        let erste = sortiert.first!.r, letzte = sortiert.last!.r
        let startMitte = waagerecht ? erste.midX : erste.midY
        let endMitte = waagerecht ? letzte.midX : letzte.midY
        let schritt = (endMitte - startMitte) / Double(sortiert.count - 1)
        gebuendelt {
            for (i, paar) in sortiert.enumerated() where i > 0 && i < sortiert.count - 1 {
                let zielMitte = startMitte + schritt * Double(i)
                if waagerecht { setzePosAbsolut(paar.a, x: zielMitte - paar.r.width / 2, y: paar.r.minY) }
                else { setzePosAbsolut(paar.a, x: paar.r.minX, y: zielMitte - paar.r.height / 2) }
            }
        }
        sichereMarkiertePositionen()
    }

    static let rasterWeite = 24.0

    /// Markierte Objekte am Raster einrasten (auf `rasterWeite` runden).
    func raste(amRaster w: Double = AppModell.rasterWeite) {
        let stücke = markierteRechtecke()
        guard !stücke.isEmpty else { return }
        gebuendelt {
            for (a, r) in stücke {
                let nx = (r.minX / w).rounded() * w
                let ny = (r.minY / w).rounded() * w
                setzePosAbsolut(a, x: nx, y: ny)
            }
        }
        sichereMarkiertePositionen()
    }

    /// Markierte Karten/Notizen in einem gleichmäßigen Gitter anordnen.
    func ordneMarkierungAlsRaster() {
        let objekte = markierung.filter { if case .ordner = $0 { return false }; return true }
        let stücke = objekte.compactMap { a in rechteck(a).map { (a, $0) } }
        guard stücke.count > 1 else { return }
        let minX = stücke.map { $0.1.minX }.min() ?? 0
        let minY = stücke.map { $0.1.minY }.min() ?? 0
        legeImGitter(stücke.map { $0.0 }, ab: CGPoint(x: minX, y: minY))
    }

    /// Mitglieder einer Mappe sauber als Gitter anordnen.
    func ordneMappeAlsRaster(_ ordnerID: Int) {
        guard let o = ordnerListe.first(where: { $0.id == ordnerID }) else { return }
        let mitglieder = eintraege.filter { $0.ordnerID == ordnerID }.map { Auswahl.karte($0.id) }
        guard mitglieder.count > 1 else { return }
        legeImGitter(mitglieder, ab: CGPoint(x: o.x + 20, y: o.y + 52), breiteGrenze: o.breite - 36)
    }

    /// Hilfsroutine: Objekte zeilenweise in ein Gitter legen (gleicher Zellabstand).
    private func legeImGitter(_ objekte: [Auswahl], ab start: CGPoint, breiteGrenze: Double? = nil) {
        let rects = objekte.compactMap { rechteck($0) }
        guard !rects.isEmpty else { return }
        let zellB = (rects.map { $0.width }.max() ?? 160) + 22
        let zellH = (rects.map { $0.height }.max() ?? 160) + 22
        let spalten = max(1, Int((breiteGrenze ?? (Double(objekte.count).squareRoot().rounded(.up) * zellB)) / zellB))
        gebuendelt {
            for (i, a) in objekte.enumerated() {
                let sp = i % spalten, ze = i / spalten
                setzePosAbsolut(a, x: start.x + Double(sp) * zellB, y: start.y + Double(ze) * zellH)
            }
        }
        for a in objekte { persistierePosition(a) }
    }

    /// Aus der aktuellen Mehrfachauswahl eine neue Mappe formen (Karten/Notizen
    /// werden Mitglieder, der Rahmen umschließt sie).
    func markierungInMappe() {
        let kartenIDs = markierung.compactMap { a -> Int? in if case .karte(let id) = a { return id }; return nil }
        let notizIDs = markierung.compactMap { a -> Int? in if case .notiz(let id) = a { return id }; return nil }
        guard kartenIDs.count + notizIDs.count >= 1, let ablage else { return }
        var rects: [CGRect] = []
        for id in kartenIDs { if let e = eintraege.first(where: { $0.id == id }) { rects.append(CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)) } }
        for id in notizIDs { if let n = notizen.first(where: { $0.id == id }) { rects.append(CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe)) } }
        guard let erste = rects.first else { return }
        let u = rects.dropFirst().reduce(erste) { $0.union($1) }
        let pad = 26.0, titel = 44.0
        let x = u.minX - pad, y = u.minY - titel, b = u.width + 2 * pad, h = u.height + titel + pad
        merke()
        Task {
            guard var o = await ablage.fuegeOrdner(board: aktivBoard, x: x, y: y) else { return }
            o.breite = b; o.hoehe = h
            ordnerListe.append(o)
            await ablage.setzeOrdnerRahmen(o.id, x: x, y: y, breite: b, hoehe: h)
            for id in kartenIDs {
                if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].ordnerID = o.id }
                await ablage.setzeKarteOrdner(id, ordnerID: o.id)
            }
            for id in notizIDs {
                if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].ordnerID = o.id }
                await ablage.setzeNotizOrdner(id, ordnerID: o.id)
            }
            einzelAuswahl(.ordner(o.id))
        }
    }

    // MARK: Verbindungen (Linien)

    func objektGetippt(_ a: Auswahl) {
        if verbindenModus {
            if let von = verbindeVon {
                if von != a { verbindeMit(von, a) }
                verbindeVon = nil
            } else {
                verbindeVon = a
            }
            auswahl = a
            markierung = [a]
        } else if NSEvent.modifierFlags.contains(.shift) {
            // Shift-Klick: zur Mehrfachauswahl hinzufügen/entfernen.
            if markierung.contains(a) { markierung.remove(a) } else { markierung.insert(a) }
            auswahl = markierung.count == 1 ? markierung.first : nil
        } else {
            einzelAuswahl(a)
        }
    }

    private func verbindeMit(_ von: Auswahl, _ nach: Auswahl) {
        guard let ablage else { return }
        merke()
        Task {
            if let v = await ablage.fuegeVerbindung(board: aktivBoard, von: von, nach: nach) {
                verbindungen.append(v)
            }
        }
    }

    func verbindungModusUmschalten() { verbindenModus.toggle(); verbindeVon = nil }
    func verbindungAbbrechen() { verbindenModus = false; verbindeVon = nil }

    func loescheVerbindung(_ id: Int) {
        guard let ablage else { return }
        merke()
        verbindungen.removeAll { $0.id == id }
        Task { await ablage.loescheVerbindung(id) }
    }

    func setzeVerbindungLabel(_ id: Int, _ text: String) {
        guard let ablage, let i = verbindungen.firstIndex(where: { $0.id == id }) else { return }
        let sauber = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if verbindungen[i].label != sauber { merke() }
        verbindungen[i].label = sauber
        Task { await ablage.setzeVerbindungLabel(id, sauber) }
    }

    private func entferneVerbindungenFuer(_ a: Auswahl) {
        verbindungen.removeAll { $0.betrifft(a) }
        Task { await ablage?.loescheVerbindungenFuer(art: a.art, id: a.kennung) }
    }

    /// Rechteck eines Objekts in Leinwand-Koordinaten (für seitliches Andocken).
    func rechteck(_ a: Auswahl) -> CGRect? {
        switch a {
        case .karte(let id):
            if let e = eintraege.first(where: { $0.id == id }), !istVerborgen(e) {
                return CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)
            }
        case .notiz(let id):
            if let n = notizen.first(where: { $0.id == id }), !istVerborgenN(n) {
                return CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe)
            }
        case .ordner(let id):
            if let o = ordnerListe.first(where: { $0.id == id }) {
                return CGRect(x: o.x, y: o.y, width: o.breite, height: o.eingeklappt ? 46 : o.hoehe)
            }
        }
        return nil
    }

    /// Gebogene Verbindung mit seitlichem Andocken: Start/Ziel an der zugewandten
    /// linken bzw. rechten Kante, Kontrollpunkte waagerecht herausgezogen.
    func linienGeometrie(_ v: Verbindung) -> LinienGeometrie? {
        guard let ra = rechteck(v.von), let rb = rechteck(v.nach) else { return nil }
        let rechts = rb.midX >= ra.midX
        let p0 = CGPoint(x: rechts ? ra.maxX : ra.minX, y: ra.midY)
        let p3 = CGPoint(x: rechts ? rb.minX : rb.maxX, y: rb.midY)
        let zug = max(45, abs(p3.x - p0.x) * 0.45)
        let c1 = CGPoint(x: p0.x + (rechts ? zug : -zug), y: p0.y)
        let c2 = CGPoint(x: p3.x + (rechts ? -zug : zug), y: p3.y)
        let mitte = CGPoint(x: (p0.x + 3 * c1.x + 3 * c2.x + p3.x) / 8,
                            y: (p0.y + 3 * c1.y + 3 * c2.y + p3.y) / 8)
        return LinienGeometrie(p0: p0, c1: c1, c2: c2, p3: p3, mitte: mitte)
    }

    /// Mittelpunkt eines Objekts in Leinwand-Koordinaten.
    func zentrum(_ a: Auswahl) -> CGPoint? {
        switch a {
        case .karte(let id):
            if let e = eintraege.first(where: { $0.id == id }), !istVerborgen(e) {
                return CGPoint(x: e.x + e.breite / 2, y: e.y + e.hoehe / 2)
            }
        case .notiz(let id):
            if let n = notizen.first(where: { $0.id == id }), !istVerborgenN(n) {
                return CGPoint(x: n.x + n.breite / 2, y: n.y + n.hoehe / 2)
            }
        case .ordner(let id):
            if let o = ordnerListe.first(where: { $0.id == id }) {
                let h = o.eingeklappt ? 46.0 : o.hoehe
                return CGPoint(x: o.x + o.breite / 2, y: o.y + h / 2)
            }
        }
        return nil
    }

    // MARK: Entfernen / neu verknüpfen

    func entferne(_ e: Eintrag) {
        guard let ablage else { return }
        merke()
        entferneVerbindungenFuer(.karte(e.id))
        eintraege.removeAll { $0.id == e.id }
        if auswahl == .karte(e.id) { auswahl = nil }
        if let vo = vorschauOrdner, let v = e.vorschau {
            try? FileManager.default.removeItem(at: vo.appendingPathComponent(v))
        }
        Task { await ablage.entferne(e.id) }
    }

    /// Backspace-Weg: erst Rückfrage (View setzt loeschKandidat), dann hier löschen.
    func entferneKandidaten() {
        guard let k = loeschKandidat else { return }
        switch k {
        case .karte(let id):
            if let e = eintraege.first(where: { $0.id == id }) { entferne(e) }
        case .ordner(let id):
            loescheOrdner(id)
        case .notiz(let id):
            loescheNotiz(id)
        }
        loeschKandidat = nil
    }

    /// Kontextmenü-Löschen: ebenfalls mit Rückfrage.
    func frageLoeschen(_ a: Auswahl) { loeschKandidat = a }

    var kandidatName: String {
        switch loeschKandidat {
        case .karte(let id): return eintraege.first(where: { $0.id == id })?.name ?? "Dokument"
        case .ordner(let id): return ordnerListe.first(where: { $0.id == id })?.name ?? "Mappe"
        case .notiz(let id):
            let t = notizen.first(where: { $0.id == id })?.text ?? ""
            return t.isEmpty ? "Textfeld" : t
        case .none: return ""
        }
    }

    func neuVerknuepfe(_ e: Eintrag, mit url: URL) {
        guard let ablage else { return }
        if let idx = eintraege.firstIndex(where: { $0.id == e.id }) {
            eintraege[idx].pfad = url.path
            eintraege[idx].name = url.lastPathComponent
            eintraege[idx].zustand = "ok"
        }
        let ocr = ocrAktiv
        Task {
            await ablage.aktualisierePfad(e.id, pfad: url.path)
            if let aktualisiert = eintraege.first(where: { $0.id == e.id }) { anreichern(aktualisiert, ocr: ocr) }
        }
    }

    /// Vorschau + Volltext einer Karte neu erzeugen (z. B. für INDD, die vor der
    /// verbesserten Extraktion importiert wurde).
    func neuIndiziere(_ id: Int) {
        guard let e = eintraege.first(where: { $0.id == id }) else { return }
        anreichern(e, ocr: ocrAktiv)
    }

    /// Echte Seitenvorschau einer INDD über InDesign erzeugen (opt-in).
    func rendereInDesign(_ id: Int) {
        guard let e = eintraege.first(where: { $0.id == id }), let vo = vorschauOrdner else { return }
        let alt = e.vorschau
        let name = "\(id)-\(Int(Date().timeIntervalSince1970)).png"  // Cache-Bust
        let ziel = vo.appendingPathComponent(name)
        Task.detached(priority: .utility) {
            let ok = await self.indexDrossel.mit { InDesignRender.rendere(indd: e.url, nach: ziel) }
            if ok {
                await self.setzeVorschauPersistent(id, name)
                if let a = alt { try? FileManager.default.removeItem(at: vo.appendingPathComponent(a)) }
            }
        }
    }

    private func setzeVorschauPersistent(_ id: Int, _ name: String) {
        VorschauCache.shared.verwerfe(name: name)
        if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].vorschau = name }
        Task { await ablage?.setzeVorschau(id, name) }
    }

    // MARK: Öffnen & Finder

    func oeffne(_ e: Eintrag) {
        // Weblink → im Standardbrowser öffnen (vom Nutzer selbst hinterlegte Adresse).
        if e.kategorie == .weblink {
            if let w = e.webURL { NSWorkspace.shared.open(w) }
            return
        }
        let url = e.url
        guard FileManager.default.fileExists(atPath: url.path) else { markiereDefekt(e.id); return }
        // Externer Ordner → im Finder öffnen.
        if e.kategorie == .ordnerExtern {
            NSWorkspace.shared.open(url)
            return
        }
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func zeigeImFinder(_ e: Eintrag) {
        guard FileManager.default.fileExists(atPath: e.pfad) else { markiereDefekt(e.id); return }
        NSWorkspace.shared.activateFileViewerSelecting([e.url])
    }

    func oeffneMit(_ e: Eintrag) { NSWorkspace.shared.activateFileViewerSelecting([e.url]) }

    private func markiereDefekt(_ id: Int) {
        if let idx = eintraege.firstIndex(where: { $0.id == id }) { eintraege[idx].zustand = "defekt" }
        Task { await ablage?.setzeZustand(id, "defekt") }
    }

    /// Prüft im HINTERGRUND, ob die referenzierten Dateien noch existieren – die
    /// `fileExists`-Aufrufe (teuer, v. a. in der Nextcloud) blockieren so nicht
    /// mehr den Canvas-Wechsel.
    private func pruefeVerknuepfungen() {
        let zuPruefen: [(id: Int, pfad: String, zustand: String, lz: String?)] = eintraege.compactMap {
            $0.kategorie == .weblink ? nil : (id: $0.id, pfad: $0.pfad, zustand: $0.zustand, lz: $0.lesezeichen)
        }
        guard !zuPruefen.isEmpty else { return }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var zustaende: [(Int, String)] = []
            var heilungen: [(Int, URL)] = []
            for e in zuPruefen {
                if fm.fileExists(atPath: e.pfad) {
                    if e.zustand != "ok" { zustaende.append((e.id, "ok")) }
                    continue
                }
                // Datei fehlt am alten Pfad → über das Lesezeichen am neuen Ort suchen.
                // Nur heilen, wenn das Bookmark frisch ist ODER der Dateiname passt –
                // sonst könnte ein veraltetes Bookmark stumm auf die FALSCHE Datei zeigen.
                if let lz = e.lz, let r = Lesezeichen.aufloese(lz), fm.fileExists(atPath: r.url.path),
                   (!r.veraltet || r.url.lastPathComponent == (e.pfad as NSString).lastPathComponent) {
                    heilungen.append((e.id, r.url))
                } else if e.zustand != "defekt" {
                    zustaende.append((e.id, "defekt"))
                }
            }
            guard !zustaende.isEmpty || !heilungen.isEmpty else { return }
            await self.wendeHeilungAn(heilungen, zustaende: zustaende)
        }
    }

    private func wendeHeilungAn(_ heilungen: [(Int, URL)], zustaende: [(Int, String)]) async {
        for (id, url) in heilungen {
            if let e = eintraege.first(where: { $0.id == id }) {
                neuVerknuepfe(e, mit: url)              // Pfad/Name aktualisieren, neu indizieren
                if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].lesezeichen = nil }
                if let aktualisiert = eintraege.first(where: { $0.id == id }) { erzeugeLesezeichen(aktualisiert) }
            }
        }
        for (id, soll) in zustaende {
            if let idx = eintraege.firstIndex(where: { $0.id == id }) { eintraege[idx].zustand = soll }
            await ablage?.setzeZustand(id, soll)
        }
    }

    // MARK: Lesezeichen (robuste Referenzen)

    /// Für eine neue Karte im Hintergrund ein Datei-Lesezeichen anlegen.
    func erzeugeLesezeichen(_ e: Eintrag) {
        guard e.istDatei || e.istOrdnerRef, e.lesezeichen == nil else { return }
        let id = e.id, url = e.url
        Task.detached(priority: .utility) {
            guard let b = Lesezeichen.erzeuge(url) else { return }
            await self.speichereLesezeichen(id, b)
        }
    }

    private func speichereLesezeichen(_ id: Int, _ base64: String) {
        if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].lesezeichen = base64 }
        Task { await ablage?.setzeLesezeichen(id, base64) }
    }

    /// Alle Datei-/Ordner-Karten ohne Lesezeichen absichern (für Alt-Bestände).
    func sichereAlleLesezeichen() {
        let offen = eintraege.filter { ($0.istDatei || $0.istOrdnerRef) && $0.lesezeichen == nil && !$0.defekt }
        for e in offen { erzeugeLesezeichen(e) }
        if var b = gesundheit { b.ohneLesezeichen = 0; gesundheit = b }
    }

    // MARK: Gesundheits-Check (fehlende Dateien, tote Links, Dubletten)

    func starteGesundheitsCheck() {
        gesundheitLaeuft = true
        let snap = eintraege                       // Wert-Schnappschuss für den Hintergrund
        let links = eintraege.filter { $0.istWeblink }
        linkToken += 1
        let token = linkToken
        Task {
            // Dateiexistenz + Dubletten im Hintergrund prüfen (fileExists blockiert
            // sonst den MainActor, v. a. bei Nextcloud/Netzlaufwerken → UI-Freeze).
            let roh = await Task.detached(priority: .utility) { () -> (fehlende: [Eintrag], dubletten: [[Eintrag]], ohne: Int) in
                let fm = FileManager.default
                let fehlende = snap.filter { ($0.istDatei || $0.istOrdnerRef) && !fm.fileExists(atPath: $0.pfad) }
                let fehlendeIDs = Set(fehlende.map { $0.id })
                var gruppen: [String: [Eintrag]] = [:]
                for e in snap where e.istDatei || e.istOrdnerRef { gruppen[e.pfad, default: []].append(e) }
                let dubletten = gruppen.values.filter { $0.count > 1 }
                    .map { $0.sorted { $0.id < $1.id } }.sorted { $0[0].name.lowercased() < $1[0].name.lowercased() }
                let ohne = snap.filter {
                    ($0.istDatei || $0.istOrdnerRef) && $0.lesezeichen == nil && !fehlendeIDs.contains($0.id)
                }.count
                return (fehlende, dubletten, ohne)
            }.value
            guard token == linkToken else { return }

            var bericht = GesundheitsBericht(fehlende: roh.fehlende, toteLinks: [], dubletten: roh.dubletten,
                                             linksGeprueft: false, ohneLesezeichen: roh.ohne)
            gesundheit = bericht

            // Web-Links der Reihe nach prüfen.
            var tot: [Eintrag] = []
            for l in links {
                let ok = await WebErfassung.erreichbar(l.pfad)
                if !ok { tot.append(l) }
            }
            guard token == linkToken else { return }
            bericht.toteLinks = tot
            bericht.linksGeprueft = true
            gesundheit = bericht
            gesundheitLaeuft = false
        }
    }

    /// Aus einem Panel heraus zu einer Karte springen (schließt die Sheets).
    func springeZuKarte(_ id: Int) {
        zeigeGesundheit = false
        zeigeReparatur = false
        zentriere(id)
    }

    // MARK: Suche

    private func sucheAnstossen() {
        guard let ablage else { trefferIDs = nil; return }
        sucheToken += 1
        let token = sucheToken
        let text = suchtext
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)   // Debounce: nur die letzte Eingabe sucht
            guard token == sucheToken else { return }
            let ids = await ablage.suche(text)
            if token == sucheToken { trefferIDs = ids }
        }
    }

    func passt(_ e: Eintrag) -> Bool {
        if let s = symbolFilter, e.symbol != s { return false }
        guard let treffer = trefferIDs else { return true }
        return treffer.contains(e.id)
    }
    /// Notizen/Mappen kennt die Volltextsuche nicht – sie reagieren nur auf den Symbolfilter.
    func passtN(_ n: Notiz) -> Bool { symbolFilter == nil || n.symbol == symbolFilter }
    func passtO(_ o: Ordner) -> Bool { symbolFilter == nil || o.symbol == symbolFilter }

    /// Nach einem Symbol filtern (Klick aufs Abzeichen): gleiches Symbol → aus.
    func filtereNachSymbol(_ symbol: String) {
        guard !symbol.isEmpty else { return }
        symbolFilter = (symbolFilter == symbol) ? nil : symbol
    }
    func symbolFilterAus() { symbolFilter = nil }

    // MARK: Schnellsuche (⌘K) über alle Leinwände

    func oeffnePalette() {
        paletteText = ""
        paletteTreffer = []
        zeigePalette = true
    }

    private func paletteSucheAnstossen() {
        guard let ablage else { paletteTreffer = []; return }
        palToken += 1
        let token = palToken
        let text = paletteText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { paletteTreffer = []; return }
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)   // Debounce
            guard token == palToken else { return }
            let treffer = await ablage.globalSuche(text)
            if token == palToken { paletteTreffer = treffer }
        }
    }

    /// Einen Schnellsuche-Treffer ansteuern: ggf. Leinwand wechseln, dann zentrieren.
    func springeZu(_ t: GlobalTreffer) {
        zeigePalette = false
        if t.boardID == aktivBoard {
            zentriere(t.id)
        } else {
            nachLadenZentriere = t.id
            wechsleBoard(t.boardID)
        }
    }

    // MARK: Schlagworte (Tags)

    func setzeTags(_ id: Int, _ roh: String) {
        guard let ablage, let i = eintraege.firstIndex(where: { $0.id == id }) else { return }
        merke()
        // Normalisiert als Leerzeichen-getrennte Liste speichern.
        let sauber = eintraege[i].tagsNormalisiert(roh)
        eintraege[i].tags = sauber
        let e = eintraege[i]
        Task {
            await ablage.setzeTags(id, sauber)
            anreichern(e, ocr: false)   // Tags in den Volltext aufnehmen
        }
    }

    func fuegeTag(_ id: Int, _ tag: String) {
        guard let e = eintraege.first(where: { $0.id == id }) else { return }
        setzeTags(id, (e.tagListe + [tag]).joined(separator: " "))
    }
    func entferneTag(_ id: Int, _ tag: String) {
        guard let e = eintraege.first(where: { $0.id == id }) else { return }
        setzeTags(id, e.tagListe.filter { $0.lowercased() != tag.lowercased() }.joined(separator: " "))
    }

    /// Setzt den Suchfilter auf ein Schlagwort (Klick auf einen Tag-Chip).
    func filtereNachTag(_ tag: String) { suchtext = tag }

    /// Akzentfarbe einer Karte (v. a. Web-Links) setzen – eigener Hex-Wert.
    func setzeKarteFarbhex(_ id: Int, _ hex: String?) {
        guard let ablage else { return }
        merke()
        if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].farbhex = hex }
        Task { await ablage.setzeFarbhex(id, hex) }
    }

    // MARK: Symbole (Katalog) – auf Karten, Notizen und Mappen

    func setzeKarteSymbol(_ id: Int, _ symbol: String) {
        guard let ablage else { return }
        merke()
        if let i = eintraege.firstIndex(where: { $0.id == id }) { eintraege[i].symbol = symbol }
        Task { await ablage.setzeSymbol(id, symbol) }
    }
    func setzeNotizSymbol(_ id: Int, _ symbol: String) {
        guard let ablage else { return }
        merke()
        if let i = notizen.firstIndex(where: { $0.id == id }) { notizen[i].symbol = symbol }
        Task { await ablage.setzeNotizSymbol(id, symbol) }
    }
    func setzeOrdnerSymbol(_ id: Int, _ symbol: String) {
        guard let ablage else { return }
        merke()
        if let i = ordnerListe.firstIndex(where: { $0.id == id }) { ordnerListe[i].symbol = symbol }
        Task { await ablage.setzeOrdnerSymbol(id, symbol) }
    }

    // MARK: Übergeordnete Rahmen / Bereiche

    func neuerRahmen() {
        guard let ablage else { return }
        merke()
        // Großzügiger Bereich um den aktuellen Blickausschnitt.
        let bx = (-schwenk.width) / zoom - 120
        let by = (-schwenk.height) / zoom - 120
        let bw = max(1000, leinwandGroesse.width / zoom + 240)
        let bh = max(700, leinwandGroesse.height / zoom + 240)
        let reihe = (rahmenListe.map { $0.reihenfolge }.max() ?? -1) + 1
        let farbe = rahmenListe.count % Design.objektFarben.count
        let board = aktivBoard
        Task {
            if let r = await ablage.fuegeRahmen(board: board, name: "Bereich \(rahmenListe.count + 1)",
                                                x: bx, y: by, breite: bw, hoehe: bh,
                                                farbe: farbe, reihenfolge: reihe) {
                rahmenListe.append(r)
                aktiverRahmen = r.id
                springeZuRahmen(r.id)
            }
        }
    }

    func verschiebeRahmen(_ id: Int, dx: Double, dy: Double) {
        guard let i = rahmenListe.firstIndex(where: { $0.id == id }) else { return }
        rahmenListe[i].x += dx; rahmenListe[i].y += dy
    }
    func skaliereRahmen(_ id: Int, breite: Double, hoehe: Double) {
        guard let i = rahmenListe.firstIndex(where: { $0.id == id }) else { return }
        rahmenListe[i].breite = breite; rahmenListe[i].hoehe = hoehe
    }
    func sichereRahmen(_ id: Int) {
        guard let ablage, let r = rahmenListe.first(where: { $0.id == id }) else { return }
        Task { await ablage.setzeRahmenGeometrie(id, x: r.x, y: r.y, breite: r.breite, hoehe: r.hoehe) }
    }
    func benenneRahmen(_ id: Int, _ name: String) {
        guard let ablage else { return }
        let sauber = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sauber.isEmpty else { return }
        if let i = rahmenListe.firstIndex(where: { $0.id == id }) { rahmenListe[i].name = sauber }
        Task { await ablage.benenneRahmen(id, name: sauber) }
    }
    func setzeRahmenFarbe(_ id: Int, _ farbe: Int) {
        guard let ablage else { return }
        merke()
        if let i = rahmenListe.firstIndex(where: { $0.id == id }) { rahmenListe[i].farbe = farbe }
        Task { await ablage.setzeRahmenFarbe(id, farbe) }
    }
    func loescheRahmen(_ id: Int) {
        guard let ablage else { return }
        merke()
        rahmenListe.removeAll { $0.id == id }
        if aktiverRahmen == id { aktiverRahmen = nil }
        Task { await ablage.loescheRahmen(id) }
    }

    /// Kamera auf einen Bereich fahren (mit Rand).
    func springeZuRahmen(_ id: Int) {
        guard let r = rahmenListe.first(where: { $0.id == id }) else { return }
        aktiverRahmen = id
        einpassen(CGRect(x: r.x, y: r.y, width: r.breite, height: r.hoehe), rand: 60)
    }

    // MARK: Kamera-Einpassen / Zoomstufen

    /// Ein Rechteck (Leinwand-Koordinaten) in den sichtbaren Ausschnitt einpassen.
    func einpassen(_ rect: CGRect, rand: Double = 80) {
        let size = leinwandGroesse
        guard size.width > 20, size.height > 20, rect.width > 1, rect.height > 1 else { return }
        let verfW = size.width - 2 * rand
        let verfH = size.height - 2 * rand
        let z = min(max(min(verfW / rect.width, verfH / rect.height), 0.25), 4)
        zoom = z
        schwenk = CGSize(width: size.width / 2 - rect.midX * z,
                         height: size.height / 2 - rect.midY * z)
        sichereKamera()
    }

    /// ⌘0: alle Objekte der Leinwand einpassen.
    func alleEinpassen() {
        var rects: [CGRect] = []
        for e in eintraege where !istVerborgen(e) { rects.append(CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)) }
        for n in notizen where !istVerborgenN(n) { rects.append(CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe)) }
        for o in ordnerListe { rects.append(CGRect(x: o.x, y: o.y, width: o.breite, height: o.eingeklappt ? 46 : o.hoehe)) }
        for r in rahmenListe { rects.append(CGRect(x: r.x, y: r.y, width: r.breite, height: r.hoehe)) }
        guard let erste = rects.first else {
            zoom = 1; schwenk = .zero; sichereKamera(); return
        }
        let gesamt = rects.dropFirst().reduce(erste) { $0.union($1) }
        einpassen(gesamt, rand: 90)
    }

    func zoomStufe(_ faktor: Double) {
        // Um die Bildschirmmitte zoomen, damit nichts „wegläuft".
        let size = leinwandGroesse
        let z = min(max(zoom * faktor, 0.25), 4)
        if size.width > 20 {
            let mx = size.width / 2, my = size.height / 2
            let wx = (mx - schwenk.width) / zoom, wy = (my - schwenk.height) / zoom
            schwenk = CGSize(width: mx - wx * z, height: my - wy * z)
        }
        zoom = z
        sichereKamera()
    }
    func zoomZuruecksetzen() { zoom = 1; schwenk = .zero; sichereKamera() }

    /// Kamera so schwenken, dass ein Leinwandpunkt in die Bildschirmmitte rückt
    /// (für die Mini-Karte).
    func zentriereLeinwand(_ p: CGPoint) {
        let size = leinwandGroesse
        guard size.width > 20 else { return }
        schwenk = CGSize(width: size.width / 2 - p.x * zoom, height: size.height / 2 - p.y * zoom)
        sichereKameraVerzoegert()
    }

    /// Umschließendes Rechteck aller Objekte (Leinwand-Koordinaten) – für Export/Einpassen.
    func inhaltRechteck() -> CGRect? {
        var rects: [CGRect] = []
        for e in eintraege where !istVerborgen(e) { rects.append(CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)) }
        for n in notizen where !istVerborgenN(n) { rects.append(CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe)) }
        for o in ordnerListe { rects.append(CGRect(x: o.x, y: o.y, width: o.breite, height: o.eingeklappt ? 46 : o.hoehe)) }
        for r in rahmenListe { rects.append(CGRect(x: r.x, y: r.y, width: r.breite, height: r.hoehe)) }
        guard let erste = rects.first else { return nil }
        return rects.dropFirst().reduce(erste) { $0.union($1) }
    }

    // MARK: Export (Bild / PDF)

    @Published var exportMeldung: String?   // kurze Rückmeldung nach dem Export

    func exportiereLeinwand(alsPDF: Bool) {
        guard let dir = dbOrt, let inhalt = inhaltRechteck() else {
            exportMeldung = "Die Leinwand ist leer – nichts zu exportieren."
            return
        }
        let rect = inhalt.insetBy(dx: -48, dy: -48)
        // Auswahl-Rahmen für die Ausgabe kurz ausblenden.
        let altAuswahl = auswahl, altMark = markierung
        auswahl = nil; markierung = []
        let daten: Data? = alsPDF
            ? LeinwandExport.pdf(self, rect: rect)
            : LeinwandExport.bild(self, rect: rect, skala: 2)
        auswahl = altAuswahl; markierung = altMark
        guard let d = daten else { exportMeldung = "Export fehlgeschlagen."; return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmm"
        let basis = boards.first(where: { $0.id == aktivBoard })?.name ?? "Leinwand"
        let sauber = basis.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let name = "Fundus-\(sauber)-\(f.string(from: Date())).\(alsPDF ? "pdf" : "png")"
        let url = dir.appendingPathComponent(name)
        do {
            try d.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            exportMeldung = "Exportiert: \(name)"
        } catch {
            exportMeldung = "Export konnte nicht gespeichert werden."
        }
    }

    // MARK: Teilen (Paket-Export, Drucken)

    /// Referenzierte Dateien + Manifest als weitergebbares Paket exportieren.
    func exportierePaket(nurAuswahl: Bool) {
        let liste: [Eintrag]
        if nurAuswahl {
            let auswahlMenge: Set<Auswahl> = markierung.isEmpty ? (auswahl.map { [$0] } ?? []) : markierung
            let ids = Set(auswahlMenge.compactMap { a -> Int? in if case .karte(let id) = a { return id }; return nil })
            liste = eintraege.filter { ids.contains($0.id) }
        } else {
            liste = eintraege
        }
        guard !liste.isEmpty else {
            exportMeldung = nurAuswahl ? "Keine Karten ausgewählt." : "Die Leinwand ist leer."
            return
        }
        guard let ziel = Dateiauswahl.paketOrdner() else { return }
        let name = boards.first(where: { $0.id == aktivBoard })?.name ?? "Leinwand"
        exportMeldung = "Paket wird erstellt …"
        Task {
            let erg = await Task.detached { Paket.exportiere(eintraege: liste, boardName: name, ziel: ziel) }.value
            if erg.ok, let o = erg.ordner { NSWorkspace.shared.activateFileViewerSelecting([o]) }
            exportMeldung = erg.meldung
        }
    }

    /// Die Leinwand als Bild drucken.
    func druckeLeinwand() {
        guard let inhalt = inhaltRechteck() else { exportMeldung = "Die Leinwand ist leer."; return }
        let rect = inhalt.insetBy(dx: -48, dy: -48)
        let altAuswahl = auswahl, altMark = markierung
        auswahl = nil; markierung = []
        let daten = LeinwandExport.bild(self, rect: rect, skala: 2)
        auswahl = altAuswahl; markierung = altMark
        guard let d = daten, let bild = NSImage(data: d) else { exportMeldung = "Druck fehlgeschlagen."; return }
        let ansicht = NSImageView(frame: NSRect(origin: .zero, size: bild.size))
        ansicht.image = bild
        ansicht.imageScaling = .scaleProportionallyUpOrDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.orientation = bild.size.width >= bild.size.height ? .landscape : .portrait
        let druck = NSPrintOperation(view: ansicht, printInfo: info)
        druck.showsPrintPanel = true
        druck.run()
    }

    /// Zoom zu einem festen Punkt (Mauszeiger) – der Leinwandpunkt unter dem Cursor
    /// bleibt an Ort und Stelle, wie beim Scrollrad-Zoom im Browser-Whiteboard.
    func zoomAnPunkt(_ faktor: Double, punkt: CGPoint) {
        let z = min(max(zoom * faktor, 0.25), 4)
        guard z != zoom else { return }
        let wx = (punkt.x - schwenk.width) / zoom
        let wy = (punkt.y - schwenk.height) / zoom
        schwenk = CGSize(width: punkt.x - wx * z, height: punkt.y - wy * z)
        zoom = z
        sichereKameraVerzoegert()
    }

    /// Kamera erst nach kurzer Ruhe sichern – damit Scroll-Zoom nicht bei jedem
    /// Tick in die Datenbank schreibt.
    private var kameraSpeicherAufgabe: Task<Void, Never>?
    func sichereKameraVerzoegert() {
        kameraSpeicherAufgabe?.cancel()
        kameraSpeicherAufgabe = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            self.sichereKamera()
        }
    }

    // MARK: Suchergebnisse

    /// Treffer als Liste (nur Karten – Dateien, Ordner, Links; Name/Inhalt via FTS).
    var sucheTreffer: [Eintrag] {
        guard let ids = trefferIDs else { return [] }
        return eintraege.filter { ids.contains($0.id) }
    }

    /// Ein Suchergebnis in den Mittelpunkt schieben und auswählen.
    func zentriere(_ id: Int) {
        guard let e = eintraege.first(where: { $0.id == id }) else { return }
        // In einem eingeklappten Ordner? → erst ausklappen.
        if let oid = e.ordnerID, let oi = ordnerListe.firstIndex(where: { $0.id == oid }),
           ordnerListe[oi].eingeklappt {
            ordnerListe[oi].eingeklappt = false
            Task { await ablage?.setzeOrdnerEingeklappt(oid, false) }
        }
        let mitte = CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe)
        // Zoom beibehalten, nur schwenken: Objektmitte in die Bildschirmmitte.
        let size = leinwandGroesse
        if size.width > 20 {
            schwenk = CGSize(width: size.width / 2 - mitte.midX * zoom,
                             height: size.height / 2 - mitte.midY * zoom)
            sichereKamera()
        }
        einzelAuswahl(.karte(id))
    }

    // MARK: Kamera

    func sichereKamera() {
        guard let ablage else { return }
        let z = zoom, x = schwenk.width, y = schwenk.height, b = aktivBoard
        Task { await ablage.setzeKamera(board: b, zoom: z, x: x, y: y) }
    }
}
