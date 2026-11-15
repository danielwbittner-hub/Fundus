import SwiftUI

/// Schwebende Format-Leiste – erscheint, sobald eine Notiz oder ein Ordner
/// ausgewählt ist. Bietet echte Farbkreise, einen eigenen Farbwähler und (bei
/// Notizen) die Überschriften-Stile H1/H2/Text.
struct InspektorLeiste: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        Group {
            if app.markierung.count > 1 {
                OrdnenLeiste()
            } else {
                switch app.auswahl {
                case .notiz(let id): notizLeiste(id)
                case .ordner(let id): ordnerLeiste(id)
                case .karte(let id): karteLeiste(id)
                default: EmptyView()
                }
            }
        }
    }

    @ViewBuilder private func karteLeiste(_ id: Int) -> some View {
        if let e = app.eintraege.first(where: { $0.id == id }) {
            rahmen {
                Image(systemName: "tag").font(.system(size: 12)).foregroundStyle(Design.neonCyan)
                TagWerkstatt(id: id, tags: e.tagListe)
            }
        }
    }

    @ViewBuilder private func notizLeiste(_ id: Int) -> some View {
        if let n = app.notizen.first(where: { $0.id == id }) {
            rahmen {
                StilWahl(stil: n.stil) { app.setzeNotizStil(id, $0) }
                teiler
                if n.zettel {
                    // Zettel: kräftige Füllfarbe (+ eigener Wähler).
                    FarbWahl(palette: Design.objektFarben,
                             aktuell: Design.farbe(index: n.farbe, hex: n.farbhex)) {
                        app.setzeNotizFarbhex(id, $0)
                    }
                } else {
                    // Freies Textfeld/Überschrift: nur helle Pastell-Textfarben.
                    FarbWahl(palette: Design.textPastell, eigeneFarbe: false,
                             aktuell: Design.notizTextFarbe(farbe: n.farbe, hex: n.farbhex)) {
                        app.setzeNotizFarbhex(id, $0)
                    }
                }
            }
        }
    }

    @ViewBuilder private func ordnerLeiste(_ id: Int) -> some View {
        if let o = app.ordnerListe.first(where: { $0.id == id }) {
            rahmen {
                Text("Mappenfarbe").font(Design.grotesk(11, gewicht: .medium))
                    .foregroundStyle(Design.gedaempft)
                teiler
                FarbWahl(aktuell: Design.farbe(index: o.farbe, hex: o.farbhex)) {
                    app.setzeOrdnerFarbhex(id, $0)
                }
            }
        }
    }

    private var teiler: some View {
        Rectangle().fill(Design.rahmen).frame(width: 1, height: 18)
    }

    private func rahmen<Inhalt: View>(@ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        HStack(spacing: 12) { inhalt() }
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Design.paneel, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}

/// Farbkreise (+ optional eigener Farbwähler).
struct FarbWahl: View {
    var palette: [Color] = Design.objektFarben
    var eigeneFarbe: Bool = true
    let aktuell: Color
    let setzen: (String) -> Void
    @State private var eigen: Color = .white

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(palette.enumerated()), id: \.offset) { _, c in
                Circle()
                    .fill(c)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white,
                        lineWidth: c.hexString == aktuell.hexString ? 2.5 : 0))
                    .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                    .contentShape(Circle())
                    .onTapGesture { setzen(c.hexString) }
            }
            if eigeneFarbe {
                Rectangle().fill(Design.rahmen).frame(width: 1, height: 18)
                ColorPicker("", selection: $eigen, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)
                    .onChange(of: eigen) { _, c in setzen(c.hexString) }
                    .help("Eigene Farbe")
            }
        }
        .onAppear { eigen = aktuell }
    }
}

/// Mehrfachauswahl: schwebende „Ordnen"-Leiste – Ausrichten, Verteilen,
/// Raster und „In Mappe".
struct OrdnenLeiste: View {
    @EnvironmentObject var app: AppModell

    private var anzahl: Int { app.markierung.count }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(anzahl)")
                .font(Design.grotesk(11, gewicht: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Design.neon))
            knopf("rectangle.3.group", "In Mappe fassen") { app.markierungInMappe() }
            teiler
            // Ausrichten
            knopf("align.horizontal.left", "Links ausrichten") { app.richteAus(.links) }
            knopf("align.horizontal.center", "Horizontal zentrieren") { app.richteAus(.mitteH) }
            knopf("align.horizontal.right", "Rechts ausrichten") { app.richteAus(.rechts) }
            knopf("align.vertical.top", "Oben ausrichten") { app.richteAus(.oben) }
            knopf("align.vertical.center", "Vertikal zentrieren") { app.richteAus(.mitteV) }
            knopf("align.vertical.bottom", "Unten ausrichten") { app.richteAus(.unten) }
            teiler
            // Verteilen
            knopf("arrow.left.and.right", "Waagerecht verteilen", aus: anzahl < 3) { app.verteile(waagerecht: true) }
            knopf("arrow.up.and.down", "Senkrecht verteilen", aus: anzahl < 3) { app.verteile(waagerecht: false) }
            teiler
            // Raster
            knopf("grid", "Am Raster einrasten") { app.raste() }
            knopf("square.grid.3x3", "Als Gitter anordnen") { app.ordneMarkierungAlsRaster() }
            teiler
            knopf("shippingbox", "Auswahl als Paket exportieren …") { app.exportierePaket(nurAuswahl: true) }
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Design.paneel, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var teiler: some View {
        Rectangle().fill(Design.rahmen).frame(width: 1, height: 18)
    }

    private func knopf(_ symbol: String, _ titel: String, aus: Bool = false, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .foregroundStyle(Design.paneelInhalt).frame(width: 28, height: 26)
        }
        .buttonStyle(.plain).disabled(aus).opacity(aus ? 0.35 : 1).help(titel)
    }
}

/// Schlagwort-Editor für eine Karte: vorhandene Tags als entfernbare Chips plus
/// ein Feld zum Hinzufügen. Klick auf einen Chip filtert die Leinwand danach.
struct TagWerkstatt: View {
    @EnvironmentObject var app: AppModell
    let id: Int
    let tags: [String]
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    var body: some View {
        HStack(spacing: 7) {
            ForEach(tags, id: \.self) { t in
                HStack(spacing: 4) {
                    Text(t).font(Design.grotesk(11.5, gewicht: .medium)).foregroundStyle(.white)
                        .onTapGesture { app.filtereNachTag(t) }
                    Button { app.entferneTag(id, t) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Design.neonCyan.opacity(0.22)))
                .overlay(Capsule().strokeBorder(Design.neonCyan.opacity(0.5), lineWidth: 0.5))
                .help("Klick filtert nach „\(t)“ · ✕ entfernt")
            }
            TextField("+ Schlagwort", text: $entwurf)
                .textFieldStyle(.plain).font(Design.grotesk(12))
                .foregroundStyle(.white).frame(width: 96).focused($fokus)
                .onSubmit(hinzufuegen)
        }
    }

    private func hinzufuegen() {
        let neu = Eintrag.zerlegeTags(entwurf)
        for t in neu { app.fuegeTag(id, t) }
        entwurf = ""
        fokus = true
    }
}

/// Kompakte, nicht-editierbare Tag-Chips (auf den Karten). Klick filtert.
struct TagChips: View {
    @EnvironmentObject var app: AppModell
    let tags: [String]
    var maximal = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(maximal), id: \.self) { t in
                Text(t)
                    .font(Design.grotesk(9, gewicht: .semibold))
                    .foregroundStyle(Design.akzent)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(Design.akzent.opacity(0.14)))
                    .onTapGesture { app.filtereNachTag(t) }
            }
            if tags.count > maximal {
                Text("+\(tags.count - maximal)")
                    .font(Design.grotesk(9, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
            }
        }
    }
}

/// Überschriften-Stile H1 / H2 / Text.
struct StilWahl: View {
    let stil: Int
    let setzen: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            knopf("H1", 2)
            knopf("H2", 1)
            knopf("Text", 0)
        }
    }

    private func knopf(_ titel: String, _ wert: Int) -> some View {
        Button { setzen(wert) } label: {
            Text(titel)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(stil == wert ? AnyShapeStyle(Design.neon)
                                         : AnyShapeStyle(Color.white.opacity(0.08)),
                            in: Capsule())
                .foregroundStyle(stil == wert ? .white : Design.gedaempft)
        }
        .buttonStyle(.plain)
    }
}
