import SwiftUI

/// Kuratierter Katalog von SF-Symbolen, die man Karten, Notizen und Mappen
/// zuordnen kann – thematisch gruppiert, mit deutschen Suchbegriffen.
enum Symbolkatalog {
    struct Eintrag: Identifiable, Hashable {
        let name: String        // SF-Symbol-Name
        let worte: [String]     // deutsche Suchbegriffe
        var id: String { name }
    }
    struct Gruppe: Identifiable {
        let titel: String
        let symbole: [Eintrag]
        var id: String { titel }
    }

    static let gruppen: [Gruppe] = [
        Gruppe(titel: "Status", symbole: [
            Eintrag(name: "checkmark.circle.fill", worte: ["haken", "erledigt", "ok", "fertig"]),
            Eintrag(name: "star.fill", worte: ["stern", "wichtig", "favorit"]),
            Eintrag(name: "flag.fill", worte: ["flagge", "fahne", "markierung"]),
            Eintrag(name: "exclamationmark.triangle.fill", worte: ["achtung", "warnung", "wichtig"]),
            Eintrag(name: "clock.fill", worte: ["uhr", "zeit", "wartet", "später"]),
            Eintrag(name: "lock.fill", worte: ["schloss", "gesperrt", "fest"]),
            Eintrag(name: "hand.thumbsup.fill", worte: ["daumen", "gut", "freigabe"]),
            Eintrag(name: "bolt.fill", worte: ["blitz", "dringend", "schnell"]),
            Eintrag(name: "hourglass", worte: ["sanduhr", "läuft", "offen"]),
            Eintrag(name: "xmark.octagon.fill", worte: ["stopp", "nein", "abgelehnt"]),
        ]),
        Gruppe(titel: "Arbeit", symbole: [
            Eintrag(name: "doc.fill", worte: ["dokument", "datei", "blatt"]),
            Eintrag(name: "pencil", worte: ["stift", "bearbeiten", "entwurf"]),
            Eintrag(name: "camera.fill", worte: ["kamera", "foto", "bild"]),
            Eintrag(name: "paintpalette.fill", worte: ["palette", "farbe", "design"]),
            Eintrag(name: "printer.fill", worte: ["drucker", "druck", "druckbogen"]),
            Eintrag(name: "scissors", worte: ["schere", "schneiden", "cut"]),
            Eintrag(name: "ruler.fill", worte: ["lineal", "maß", "layout"]),
            Eintrag(name: "briefcase.fill", worte: ["koffer", "arbeit", "projekt"]),
            Eintrag(name: "lightbulb.fill", worte: ["idee", "glühbirne", "einfall"]),
            Eintrag(name: "wrench.and.screwdriver.fill", worte: ["werkzeug", "technik", "reparatur"]),
        ]),
        Gruppe(titel: "Ordnung", symbole: [
            Eintrag(name: "tag.fill", worte: ["etikett", "schild", "label", "kategorie"]),
            Eintrag(name: "bookmark.fill", worte: ["lesezeichen", "merken"]),
            Eintrag(name: "heart.fill", worte: ["herz", "liebling", "favorit"]),
            Eintrag(name: "pin.fill", worte: ["pin", "stecknadel", "fest"]),
            Eintrag(name: "mappin", worte: ["ort", "nadel", "stelle"]),
            Eintrag(name: "tray.fill", worte: ["ablage", "eingang", "korb"]),
            Eintrag(name: "archivebox.fill", worte: ["archiv", "ablage", "kiste"]),
            Eintrag(name: "paperclip", worte: ["büroklammer", "anhang", "klammer"]),
            Eintrag(name: "list.bullet", worte: ["liste", "aufzählung", "punkte"]),
            Eintrag(name: "folder.fill", worte: ["ordner", "mappe", "sammlung"]),
        ]),
        Gruppe(titel: "Kommunikation", symbole: [
            Eintrag(name: "bubble.left.fill", worte: ["sprechblase", "kommentar", "notiz"]),
            Eintrag(name: "envelope.fill", worte: ["brief", "mail", "umschlag"]),
            Eintrag(name: "phone.fill", worte: ["telefon", "anruf"]),
            Eintrag(name: "person.fill", worte: ["person", "kontakt", "kunde"]),
            Eintrag(name: "person.2.fill", worte: ["personen", "team", "gruppe"]),
            Eintrag(name: "megaphone.fill", worte: ["megafon", "ankündigung", "werbung"]),
            Eintrag(name: "calendar", worte: ["kalender", "termin", "datum"]),
            Eintrag(name: "link", worte: ["link", "verknüpfung", "kette"]),
        ]),
        Gruppe(titel: "Orte & Pfeile", symbole: [
            Eintrag(name: "globe", worte: ["globus", "welt", "web", "internet"]),
            Eintrag(name: "map.fill", worte: ["karte", "landkarte"]),
            Eintrag(name: "house.fill", worte: ["haus", "zuhause", "start"]),
            Eintrag(name: "building.2.fill", worte: ["gebäude", "firma", "büro"]),
            Eintrag(name: "car.fill", worte: ["auto", "fahrt", "wagen"]),
            Eintrag(name: "location.fill", worte: ["standort", "position", "ort"]),
            Eintrag(name: "arrow.right", worte: ["pfeil", "rechts", "weiter"]),
            Eintrag(name: "arrow.up.right", worte: ["pfeil", "hoch", "export"]),
        ]),
        Gruppe(titel: "Marker", symbole: [
            Eintrag(name: "circle.fill", worte: ["kreis", "punkt", "marker"]),
            Eintrag(name: "square.fill", worte: ["quadrat", "kasten"]),
            Eintrag(name: "triangle.fill", worte: ["dreieck"]),
            Eintrag(name: "diamond.fill", worte: ["raute", "diamant"]),
            Eintrag(name: "seal.fill", worte: ["siegel", "plakette", "abzeichen"]),
            Eintrag(name: "number", worte: ["raute", "nummer", "hashtag"]),
            Eintrag(name: "questionmark.circle.fill", worte: ["frage", "unklar"]),
            Eintrag(name: "info.circle.fill", worte: ["info", "hinweis"]),
        ]),
    ]

    /// Alle Symbole flach (für die Suche).
    static let alle: [Eintrag] = gruppen.flatMap { $0.symbole }

    /// Symbole, die zum Suchtext passen (Name oder deutsche Begriffe).
    static func treffer(_ text: String) -> [Eintrag] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return alle }
        return alle.filter { e in
            e.name.lowercased().contains(q) || e.worte.contains { $0.contains(q) }
        }
    }
}

/// Rundes Symbol-Abzeichen auf einem Objekt (klickbar → nach Symbol filtern).
struct SymbolAbzeichen: View {
    let symbol: String
    let farbe: Color
    var groesse: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: groesse * 0.54, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)   // Glyph hebt sich auch auf hellen Farben ab
            .frame(width: groesse, height: groesse)
            .background(Circle().fill(farbe))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
            .overlay(Circle().strokeBorder(.black.opacity(0.22), lineWidth: 0.5).padding(-1))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1.5)
    }
}

/// Knopf in der Inspektor-Leiste: zeigt das aktuelle Symbol und öffnet den Katalog.
struct SymbolSteuer: View {
    let symbol: String
    let farbe: Color
    let setzen: (String) -> Void
    @State private var offen = false

    var body: some View {
        Button { offen = true } label: {
            Image(systemName: symbol.isEmpty ? "square.grid.2x2" : symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(symbol.isEmpty ? Design.paneelInhalt : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(symbol.isEmpty
                    ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(farbe)))
                .overlay(Circle().strokeBorder(.white.opacity(symbol.isEmpty ? 0.12 : 0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Symbol zuordnen")
        .popover(isPresented: $offen, arrowEdge: .bottom) {
            SymbolWaehler(aktuell: symbol, farbe: farbe, setzen: setzen)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Popover-Inhalt zum Auswählen eines Symbols aus dem Katalog.
struct SymbolWaehler: View {
    let aktuell: String
    let farbe: Color
    let setzen: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var suche = ""

    private let spalten = Array(repeating: GridItem(.fixed(34), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Symbol suchen – z. B. Stern, Haken, Ordner …", text: $suche)
                    .textFieldStyle(.plain).font(Design.grotesk(12))
                if !aktuell.isEmpty {
                    Button { setzen(""); dismiss() } label: {
                        Label("Keins", systemImage: "nosign").font(Design.grotesk(11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Symbol entfernen")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: Capsule())

            ScrollView {
                if suche.isEmpty {
                    ForEach(Symbolkatalog.gruppen) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.titel.uppercased())
                                .font(Design.grotesk(9.5, gewicht: .bold)).foregroundStyle(.secondary)
                            raster(g.symbole)
                        }.padding(.bottom, 4)
                    }
                } else {
                    let t = Symbolkatalog.treffer(suche)
                    if t.isEmpty {
                        Text("Kein Symbol gefunden.").font(Design.grotesk(12)).foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        raster(t)
                    }
                }
            }
            .frame(height: 300)
        }
        .padding(14)
        .frame(width: 322)
        // Fester, voll deckender dunkler Grund: die Symbole sind im Katalog weiß –
        // ohne dunklen Untergrund wären sie in der hellen App-Ansicht unsichtbar.
        .background(Color(red: 0.07, green: 0.09, blue: 0.15))
    }

    private func raster(_ symbole: [Symbolkatalog.Eintrag]) -> some View {
        LazyVGrid(columns: spalten, spacing: 8) {
            ForEach(symbole) { e in
                Button { setzen(e.name); dismiss() } label: {
                    Image(systemName: e.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(e.name == aktuell ? Color.white : Color.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(e.name == aktuell ? AnyShapeStyle(farbe) : AnyShapeStyle(Color.primary.opacity(0.06)))
                        )
                }
                .buttonStyle(.plain)
                .help(e.worte.first ?? e.name)
            }
        }
    }
}
