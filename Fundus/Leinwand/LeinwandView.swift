import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Leinwand { static let raum = "leinwand" }

/// Eine der vier Ecken (fürs Skalieren).
enum Ecke: CaseIterable {
    case obenLinks, obenRechts, untenLinks, untenRechts
    var rechts: Bool { self == .obenRechts || self == .untenRechts }
    var unten: Bool { self == .untenLinks || self == .untenRechts }
    var ausrichtung: Alignment {
        switch self {
        case .obenLinks: return .topLeading
        case .obenRechts: return .topTrailing
        case .untenLinks: return .bottomLeading
        case .untenRechts: return .bottomTrailing
        }
    }
    var symbol: String { (rechts == unten) ? "arrow.down.right.and.arrow.up.left"
                                            : "arrow.up.right.and.arrow.down.left" }

    /// Neues Rechteck: die gegenüberliegende Ecke bleibt fest.
    func rechteck(start: CGRect, dx: Double, dy: Double,
                  minB: Double, minH: Double, verh: Double?) -> CGRect {
        var w = rechts ? start.width + dx : start.width - dx
        var h = unten ? start.height + dy : start.height - dy
        w = max(minB, w)
        if let verh, verh > 0 {
            h = w / verh
            if h < minH { h = minH; w = h * verh }
        } else {
            h = max(minH, h)
        }
        let ankerX = rechts ? start.minX : start.maxX
        let ankerY = unten ? start.minY : start.maxY
        let x = rechts ? ankerX : ankerX - w
        let y = unten ? ankerY : ankerY - h
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Vier Eck-Griffe zum Skalieren über alle Ecken. `verh != nil` hält das
/// Seitenverhältnis (für Karten).
struct EckGriffe: View {
    @EnvironmentObject var app: AppModell
    var farbe: Color
    var verh: Double?
    var minB: Double
    var minH: Double
    var groesse: CGFloat = 15
    let rechteck: () -> CGRect
    let beginn: () -> Void
    let aktualisiere: (CGRect) -> Void
    let ende: () -> Void
    @State private var start: CGRect?

    var body: some View {
        ZStack {
            ForEach(Ecke.allCases, id: \.self) { ecke in
                knopf(ecke)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: ecke.ausrichtung)
            }
        }
    }

    private func knopf(_ ecke: Ecke) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(farbe)
            .frame(width: groesse, height: groesse)
            .overlay(Image(systemName: ecke.symbol)
                .font(.system(size: groesse * 0.5, weight: .bold)).foregroundStyle(.white))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .padding(3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(Leinwand.raum))
                    .onChanged { g in
                        let s = start ?? rechteck()
                        if start == nil { beginn(); start = s }
                        let dx = g.translation.width / app.zoom
                        let dy = g.translation.height / app.zoom
                        aktualisiere(ecke.rechteck(start: s, dx: dx, dy: dy,
                                                   minB: minB, minH: minH, verh: verh))
                    }
                    .onEnded { _ in start = nil; ende() }
            )
    }
}

/// Freies Canvas: Karten & Ordner liegen in Leinwand-Koordinaten,
/// Schwenk + Zoom bilden sie auf den Bildschirm ab.
///   Bildschirm = Leinwand · zoom + schwenk
struct LeinwandView: View {
    @EnvironmentObject var app: AppModell
    @State private var panStart: CGSize?
    @State private var zoomStart: Double?
    @State private var istPan = false
    @State private var markierRahmen: CGRect?   // Markier-Rechteck (Container-Koordinaten)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Design.leinwandVerlauf(dunkel: app.istDunkel)
                    .contentShape(Rectangle())
                    .onTapGesture { app.leereAuswahl() }   // Deselektieren nur im Leeren
                RasterHintergrund(zoom: app.zoom, schwenk: app.schwenk, dunkel: app.istDunkel)
                // Verbindungslinien in Bildschirm-Koordinaten (Vektor, bei jedem
                // Zoom gestochen scharf – keine Pixelung durch scaleEffect).
                VerbindungenCanvas()

                ZStack(alignment: .topLeading) {
                    // Übergeordnete Bereiche ganz hinten
                    ForEach(app.rahmenListe) { r in
                        RahmenAnsicht(r: r).offset(x: r.x, y: r.y)
                    }
                    // Ordner hinten
                    ForEach(app.ordnerListe) { o in
                        OrdnerAnsicht(o: o).offset(x: o.x, y: o.y)
                    }
                    // Karten (in eingeklappten Ordnern verborgen)
                    ForEach(app.eintraege.filter { !app.istVerborgen($0) }) { e in
                        KarteAnsicht(e: e)
                            .frame(width: e.breite, height: e.hoehe, alignment: .topLeading)
                            .offset(x: e.x, y: e.y)
                            .opacity(app.passt(e) ? 1 : 0.16)
                    }
                    // Notizen ganz vorne – liegen über den Elementen
                    // (in eingeklappten Ordnern verborgen)
                    ForEach(app.notizen.filter { !app.istVerborgenN($0) }) { n in
                        NotizAnsicht(n: n)
                            .frame(width: n.breite, height: n.hoehe, alignment: .topLeading)
                            .offset(x: n.x, y: n.y)
                    }
                    // Lösch-Punkte der Verbindungen (ganz vorne, anklickbar)
                    ForEach(app.verbindungen) { v in VerbindungPunkt(v: v) }
                }
                .frame(width: 1, height: 1, alignment: .topLeading)
                // Höhere Rasterauflösung beim Hineinzoomen → Schrift/Icons bleiben
                // scharf. Auf 4× gedeckelt und quantisiert (nur an ganzen Stufen),
                // damit der Backing-Store nicht unnötig groß wird / bei jedem Tick springt.
                .environment(\.displayScale, min(4, max(2, app.zoom.rounded(.up))))
                .scaleEffect(app.zoom, anchor: .topLeading)
                .offset(app.schwenk)

                // Markier-Rechteck
                if let r = markierRahmen {
                    Rectangle().fill(Design.neonCyan.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Design.neonCyan, lineWidth: 1))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(leinwandGeste)
            .simultaneousGesture(zoomGeste)
            .onDrop(of: [UTType.fileURL, UTType.url, UTType.plainText], delegate: AblegeZiel(app: app) { punkt in
                CGPoint(x: (punkt.x - app.schwenk.width) / app.zoom,
                        y: (punkt.y - app.schwenk.height) / app.zoom)
            })
            .clipped()
            // Stabiler Bezugsrahmen für alle Drags – verhindert das „Wackeln",
            // weil die Translation nicht relativ zum mitbewegten Objekt gemessen wird.
            .coordinateSpace(name: Leinwand.raum)
            .onAppear { app.leinwandGroesse = geo.size }
            .onChange(of: geo.size) { _, neu in app.leinwandGroesse = neu }
            .onContinuousHover(coordinateSpace: .local) { phase in
                if case let .active(p) = phase { app.mausPunkt = p }
            }
        }
    }

    /// Ziehen auf leerer Fläche = Rahmenauswahl. Leertaste halten + Ziehen = Schwenken.
    private var leinwandGeste: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Leinwand.raum))
            .onChanged { g in
                if panStart == nil && markierRahmen == nil {
                    istPan = app.spaceAktiv
                }
                if istPan {
                    let s = panStart ?? app.schwenk
                    if panStart == nil { panStart = s }
                    app.spaceGezogen = true
                    app.schwenk = CGSize(width: s.width + g.translation.width,
                                         height: s.height + g.translation.height)
                } else {
                    // Rechteck in Container-Koordinaten (für die Anzeige)
                    markierRahmen = CGRect(
                        x: min(g.startLocation.x, g.location.x),
                        y: min(g.startLocation.y, g.location.y),
                        width: abs(g.location.x - g.startLocation.x),
                        height: abs(g.location.y - g.startLocation.y))
                    // Rechteck in Leinwand-Koordinaten (für die Treffer)
                    let a = CGPoint(x: (g.startLocation.x - app.schwenk.width) / app.zoom,
                                    y: (g.startLocation.y - app.schwenk.height) / app.zoom)
                    let b = CGPoint(x: (g.location.x - app.schwenk.width) / app.zoom,
                                    y: (g.location.y - app.schwenk.height) / app.zoom)
                    app.markiereBereich(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                               width: abs(a.x - b.x), height: abs(a.y - b.y)))
                }
            }
            .onEnded { _ in
                if istPan { panStart = nil; app.sichereKamera() }
                markierRahmen = nil
                istPan = false
            }
    }

    private var zoomGeste: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                let z = zoomStart ?? app.zoom
                if zoomStart == nil { zoomStart = z }
                app.zoom = min(max(z * v, 0.25), 4)
            }
            .onEnded { _ in zoomStart = nil; app.sichereKamera() }
    }
}

// MARK: - Karte

struct KarteAnsicht: View {
    @EnvironmentObject var app: AppModell
    let e: Eintrag
    @State private var start: CGPoint?
    @State private var letzteTrans: CGSize = .zero
    @State private var hover = false
    @State private var ordnerInhalt: [OrdnerInhalt.Eintrag] = []
    @State private var ordnerAnzahl = 0

    private var markiert: Bool { app.istMarkiert(.karte(e.id)) }
    private var einzeln: Bool { app.auswahl == .karte(e.id) }

    private var randStil: AnyShapeStyle {
        if e.defekt { return AnyShapeStyle(Design.neonFuchsia) }
        if markiert || hover { return AnyShapeStyle(Design.neon) }
        return AnyShapeStyle(Design.rahmen)
    }

    var body: some View {
        kern
        .background(Design.karte)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(randStil, lineWidth: e.defekt ? 2 : (markiert ? 2.5 : (hover ? 2 : 1)))
        )
        .overlay {
            if hover || einzeln {
                EckGriffe(farbe: Design.neonCyan, verh: e.seitenverhaeltnis, minB: 120, minH: 90,
                          rechteck: { CGRect(x: e.x, y: e.y, width: e.breite, height: e.hoehe) },
                          beginn: { app.beginneAktion() },
                          aktualisiere: { app.formeKarte(e.id, $0) },
                          ende: { app.sichereKarteRahmen(e.id) })
            }
        }
        .overlay(alignment: .top) {
            if hover && !e.defekt { ziehGriff.offset(y: -12) }
        }
        .shadow(color: .black.opacity(markiert || hover ? 0.5 : 0.3),
                radius: markiert || hover ? 18 : 9, y: markiert || hover ? 9 : 4)
        .scaleEffect(hover ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.14), value: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .task(id: e.pfad) { await ladeOrdnerInhalt() }
        .gesture(ziehGeste)
        .onTapGesture(count: 2) { app.oeffne(e) }
        .onTapGesture(count: 1) { app.objektGetippt(.karte(e.id)) }
        .contextMenu { menue }
        .help(e.pfad)
    }

    /// Kleiner Griff zum Herausziehen in den Finder oder eine andere App.
    private var ziehGriff: some View {
        HStack(spacing: 3) {
            Image(systemName: e.istWeblink ? "arrow.up.forward" : "square.and.arrow.up")
            Text(e.istWeblink ? "Link ziehen" : "in Finder ziehen")
        }
        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        .onDrag { ziehAnbieter() }
        .help("In den Finder oder eine andere App ziehen (kopiert die Datei)")
    }

    private func ziehAnbieter() -> NSItemProvider {
        if e.istWeblink {
            if let u = e.webURL { return NSItemProvider(object: u as NSURL) }
            return NSItemProvider(object: e.pfad as NSString)
        }
        if FileManager.default.fileExists(atPath: e.pfad) {
            return NSItemProvider(contentsOf: e.url) ?? NSItemProvider(object: e.url as NSURL)
        }
        return NSItemProvider(object: e.url as NSURL)
    }

    @ViewBuilder private var kern: some View {
        switch e.kategorie {
        case .ordnerExtern: ordnerKarte
        case .weblink:      linkKarte
        default:
            VStack(spacing: 0) {
                vorschau
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.vorschauGrund)
                    .clipped()
                fuss
            }
        }
    }

    private func ladeOrdnerInhalt() async {
        guard e.istOrdnerRef else { return }
        let url = e.url
        let paar = await Task.detached(priority: .utility) {
            OrdnerInhalt.uebersicht(url, maximal: 40)
        }.value
        ordnerInhalt = paar.liste
        ordnerAnzahl = paar.anzahl
    }

    // MARK: Externer Finder-Ordner (zeigt seinen Inhalt)

    private var ordnerFarbe: Color { Design.objektFarbe(3) }   // Bernstein – hebt sich vom Neon ab

    private var sichtbareZeilen: Int { max(3, Int((e.hoehe - 104) / 16.5)) }

    private var ordnerKarte: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: e.defekt ? "folder.badge.questionmark" : "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(e.defekt ? Design.neonFuchsia : ordnerFarbe)
                Text(e.name)
                    .font(Design.grotesk(12.5, gewicht: .semibold)).foregroundStyle(Design.tinte)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(ordnerFarbe.opacity(0.16))

            VStack(alignment: .leading, spacing: 3) {
                if e.defekt {
                    Text("Ordner nicht gefunden").font(Design.grotesk(10.5)).foregroundStyle(Design.neonFuchsia)
                } else if ordnerInhalt.isEmpty {
                    Text("leer").font(Design.grotesk(10.5)).foregroundStyle(Design.gedaempft)
                } else {
                    ForEach(ordnerInhalt.prefix(sichtbareZeilen)) { kind in
                        HStack(spacing: 6) {
                            Image(systemName: kind.istOrdner ? "folder" : "doc")
                                .font(.system(size: 9))
                                .foregroundStyle(kind.istOrdner ? ordnerFarbe : Design.gedaempft)
                            Text(kind.name).font(Design.grotesk(10.5)).foregroundStyle(Design.tinte)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                    if ordnerAnzahl > sichtbareZeilen {
                        Text("+ \(ordnerAnzahl - sichtbareZeilen) weitere")
                            .font(Design.grotesk(9.5, gewicht: .medium)).foregroundStyle(ordnerFarbe)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 5) {
                Image(systemName: "externaldrive").font(.system(size: 9)).foregroundStyle(ordnerFarbe)
                Text("\(ordnerAnzahl) Objekte · Finder-Ordner")
                    .font(Design.grotesk(9.5)).foregroundStyle(Design.gedaempft)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: Weblink

    private var linkKarte: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let vo = app.vorschauOrdner, let v = e.vorschau,
                   let bild = VorschauCache.shared.bild(ordner: vo, name: v) {
                    Image(nsImage: bild).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "globe").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Design.neonCyan)
                }
                Text(e.webHost).font(Design.grotesk(10)).foregroundStyle(Design.gedaempft)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Design.gedaempft)
            }
            Text(e.name)
                .font(Design.grotesk(12.5, gewicht: .semibold)).foregroundStyle(Design.tinte)
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            if !e.kommentar.isEmpty {
                Divider().overlay(Design.neonCyan.opacity(0.25))
                Text(e.kommentar)
                    .font(Design.grotesk(10.5)).foregroundStyle(Design.gedaempft)
                    .lineLimit(3).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if !e.tagListe.isEmpty { TagChips(tags: e.tagListe) }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Design.neonCyan.opacity(0.14), Color.clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    @ViewBuilder private var vorschau: some View {
        if let vo = app.vorschauOrdner, let v = e.vorschau,
           let bild = VorschauCache.shared.bild(ordner: vo, name: v) {
            Image(nsImage: bild).resizable().aspectRatio(contentMode: .fit).padding(4)
        } else {
            Image(nsImage: VorschauCache.shared.icon(pfad: e.pfad))
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var fuss: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Group {
                    if e.defekt {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Design.neonFuchsia)
                    } else {
                        Image(systemName: e.kategorie.symbol).foregroundStyle(Design.neon)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                Text(e.name)
                    .font(Design.grotesk(12.5, gewicht: .semibold))
                    .foregroundStyle(Design.tinte)
                    .lineLimit(2).truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !e.groesseText.isEmpty {
                Text(e.groesseText)
                    .font(Design.grotesk(9.5)).foregroundStyle(Design.gedaempft)
                    .padding(.leading, 18)
            }
            if !e.tagListe.isEmpty {
                TagChips(tags: e.tagListe).padding(.leading, 18).padding(.top, 1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private var ziehGeste: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Leinwand.raum))
            .onChanged { g in
                if app.markierung.count > 1 && app.istMarkiert(.karte(e.id)) {
                    if letzteTrans == .zero { app.beginneAktion() }
                    let dx = (g.translation.width - letzteTrans.width) / app.zoom
                    let dy = (g.translation.height - letzteTrans.height) / app.zoom
                    app.verschiebeMarkierung(dx: dx, dy: dy)
                    letzteTrans = g.translation
                } else {
                    let s = start ?? CGPoint(x: e.x, y: e.y)
                    if start == nil { app.beginneAktion(); start = s; app.einzelAuswahl(.karte(e.id)) }
                    let nx = s.x + g.translation.width / app.zoom
                    let ny = s.y + g.translation.height / app.zoom
                    app.verschiebe(e.id, x: nx, y: ny)
                    app.aktualisiereZiel(CGPoint(x: nx + e.breite / 2, y: ny + e.hoehe / 2))
                }
            }
            .onEnded { _ in
                if letzteTrans != .zero { letzteTrans = .zero; app.sichereMarkierung() }
                else { start = nil; app.sichereKarte(e.id) }
            }
    }

    @ViewBuilder private var menue: some View {
        if e.istWeblink {
            Button("Im Browser öffnen") { app.oeffne(e) }
            Button("Adresse kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.pfad, forType: .string)
            }
            Button("Link bearbeiten…") { app.starteLinkBearbeiten(e.id) }
            Divider()
            Button("Entfernen", role: .destructive) { app.frageLoeschen(.karte(e.id)) }
        } else if e.istOrdnerRef {
            Button("Im Finder öffnen") { app.oeffne(e) }
            Button("Inhalt neu einlesen") { app.neuIndiziere(e.id); Task { await ladeOrdnerInhalt() } }
            pfadMenue
            Divider()
            Button("Von der Pinnwand entfernen", role: .destructive) { app.frageLoeschen(.karte(e.id)) }
        } else {
            Button("Öffnen") { app.oeffne(e) }
            Button("Im Finder anzeigen") { app.zeigeImFinder(e) }
            Button("Öffnen mit…") { app.oeffneMit(e) }
            pfadMenue
            Divider()
            Button("Neu verknüpfen…") {
                if let url = Dateiauswahl.datei() { app.neuVerknuepfe(e, mit: url) }
            }
            Button("Vorschau neu erzeugen") { app.neuIndiziere(e.id) }
            if e.kategorie == .indesign && InDesignRender.verfuegbar {
                Button("Seitenvorschau mit InDesign rendern") { app.rendereInDesign(e.id) }
            }
            Button("Von der Pinnwand entfernen", role: .destructive) {
                app.frageLoeschen(.karte(e.id))
            }
        }
    }

    @ViewBuilder private var pfadMenue: some View {
        Menu("Pfad kopieren") {
            Button("macOS-Pfad (/)") { app.kopierePfad(e, windows: false) }
            Button("Windows-Pfad (\\)") { app.kopierePfad(e, windows: true) }
        }
    }
}

// MARK: - Ordner (Container)

struct OrdnerAnsicht: View {
    @EnvironmentObject var app: AppModell
    let o: Ordner
    @State private var letzteTrans: CGSize = .zero
    @State private var groesseStart: CGSize?
    @State private var bearbeite = false
    @State private var nameEntwurf = ""
    @FocusState private var fokus: Bool

    private var markiert: Bool { app.istMarkiert(.ordner(o.id)) }
    private var einzeln: Bool { app.auswahl == .ordner(o.id) }
    private var farbe: Color { Design.farbe(index: o.farbe, hex: o.farbhex) }
    private var zielAktiv: Bool { app.zielOrdner == o.id }

    var body: some View {
        Group { if o.eingeklappt { kompakt } else { ausgeklappt } }
            .contextMenu {
                Button(o.eingeklappt ? "Ausklappen" : "Einklappen") { app.klappeOrdner(o.id) }
                Button("Umbenennen") { starteBearbeiten() }
                Button("Inhalt als Gitter anordnen") { app.ordneMappeAlsRaster(o.id) }
                Divider()
                Button("Mappe auflösen", role: .destructive) { app.frageLoeschen(.ordner(o.id)) }
            }
    }

    // Ausgeklappt: Rahmen mit Titelleiste
    private var ausgeklappt: some View {
        VStack(spacing: 0) {
            titelleiste
            Spacer(minLength: 0)
        }
        .frame(width: o.breite, height: o.hoehe, alignment: .top)
        .background(
            // Leichter, transparenter Farbgrund in der gewählten Mappenfarbe.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(farbe.opacity(zielAktiv ? 0.22 : 0.10))
        )
        .contentShape(Rectangle())
        .onTapGesture { app.objektGetippt(.ordner(o.id)) }   // ganze Fläche wählbar/verbindbar
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder((markiert || zielAktiv) ? AnyShapeStyle(farbe)
                                                      : AnyShapeStyle(farbe.opacity(0.45)),
                              style: StrokeStyle(lineWidth: zielAktiv ? 2.5 : (markiert ? 2 : 1.5),
                                                 dash: zielAktiv ? [] : [7, 6]))
                .allowsHitTesting(false)
        )
        .shadow(color: zielAktiv ? farbe.opacity(0.5) : .clear, radius: zielAktiv ? 14 : 0)
        .overlay {
            if einzeln {
                EckGriffe(farbe: farbe, verh: nil, minB: 180, minH: 130, groesse: 18,
                          rechteck: { CGRect(x: o.x, y: o.y, width: o.breite, height: o.hoehe) },
                          beginn: { app.beginneAktion() },
                          aktualisiere: { app.formeOrdner(o.id, $0) },
                          ende: { app.sichereOrdner(o.id) })
            }
        }
    }

    private var titelleiste: some View {
        HStack(spacing: 8) {
            Button { app.klappeOrdner(o.id) } label: {
                Image(systemName: o.eingeklappt ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }.buttonStyle(.plain).foregroundStyle(farbe)

            Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(farbe)

            if bearbeite {
                TextField("Name", text: $nameEntwurf)
                    .textFieldStyle(.plain).font(Design.grotesk(12, gewicht: .semibold))
                    .foregroundStyle(.white).focused($fokus)
                    .onSubmit(commitName)
                    .frame(maxWidth: 180)
            } else {
                Text(o.name).font(Design.grotesk(12, gewicht: .semibold)).foregroundStyle(.white)
                    .onTapGesture(count: 2) { starteBearbeiten() }
            }

            Text("\(app.mitgliederZahl(o.id))")
                .font(Design.grotesk(10, gewicht: .bold)).foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(farbe.opacity(0.45)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Design.paneel)   // fester dunkler Streifen → weiße Schrift auch im Hellmodus lesbar
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15))
        .contentShape(Rectangle())
        .gesture(ziehGeste)   // Titel ziehen = Ordner verschieben
    }

    // Eingeklappt: kompakte Kachel
    private var kompakt: some View {
        HStack(spacing: 8) {
            Button { app.klappeOrdner(o.id) } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }.buttonStyle(.plain).foregroundStyle(farbe)
            Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(farbe)
            Text(o.name).font(Design.grotesk(12, gewicht: .semibold)).foregroundStyle(.white)
                .lineLimit(1)
            Text("\(app.mitgliederZahl(o.id))")
                .font(Design.grotesk(10, gewicht: .bold)).foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(farbe.opacity(0.45)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Design.paneel)   // fester dunkler Grund → weiße Schrift auch im Hellmodus lesbar
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(markiert ? AnyShapeStyle(farbe) : AnyShapeStyle(farbe.opacity(0.5)),
                          lineWidth: markiert ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { app.objektGetippt(.ordner(o.id)) }
        .gesture(ziehGeste)
    }

    /// Titelleiste ziehen → Ordner + Mitglieder verschieben (oder ganze Markierung).
    private var ziehGeste: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Leinwand.raum))
            .onChanged { g in
                let multi = app.markierung.count > 1 && app.istMarkiert(.ordner(o.id))
                if letzteTrans == .zero { app.beginneAktion() }
                if letzteTrans == .zero && !multi { app.einzelAuswahl(.ordner(o.id)) }
                let dx = (g.translation.width - letzteTrans.width) / app.zoom
                let dy = (g.translation.height - letzteTrans.height) / app.zoom
                if multi { app.verschiebeMarkierung(dx: dx, dy: dy) }
                else { app.verschiebeOrdner(o.id, dx: dx, dy: dy) }
                letzteTrans = g.translation
            }
            .onEnded { _ in
                let multi = app.markierung.count > 1 && app.istMarkiert(.ordner(o.id))
                letzteTrans = .zero
                if multi { app.sichereMarkierung() } else { app.sichereOrdner(o.id) }
            }
    }

    private func starteBearbeiten() {
        nameEntwurf = o.name
        bearbeite = true
        DispatchQueue.main.async { fokus = true }
    }
    private func commitName() {
        app.benenneOrdner(o.id, nameEntwurf)
        bearbeite = false
    }
}

// MARK: - Übergeordneter Rahmen / Bereich

struct RahmenAnsicht: View {
    @EnvironmentObject var app: AppModell
    let r: Rahmen
    @State private var letzteTrans: CGSize = .zero
    @State private var groesseStart: CGSize?
    @State private var bearbeite = false
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    private var farbe: Color { Design.objektFarbe(r.farbe) }
    private var aktiv: Bool { app.aktiverRahmen == r.id }

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(farbe.opacity(aktiv ? 0.10 : (app.optionAktiv ? 0.12 : 0.055)))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(farbe.opacity(aktiv ? 0.85 : (app.optionAktiv ? 0.75 : 0.40)),
                                  style: StrokeStyle(lineWidth: aktiv ? 2.5 : (app.optionAktiv ? 2 : 1.5),
                                                     dash: [11, 8]))
            )
            .frame(width: r.breite, height: r.hoehe)
            .allowsHitTesting(false)                 // Fläche durchklickbar – Objekte bleiben bedienbar
            // ⌥ gedrückt → ganze Fläche greifbar zum Verschieben.
            .overlay {
                if app.optionAktiv {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.001))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .gesture(ziehGeste)
                }
            }
            .overlay(alignment: .topLeading) { titelChip.padding(10) }
            .overlay {
                EckGriffe(farbe: farbe, verh: nil, minB: 400, minH: 280, groesse: 20,
                          rechteck: { CGRect(x: r.x, y: r.y, width: r.breite, height: r.hoehe) },
                          beginn: { app.beginneAktion(); app.aktiverRahmen = r.id },
                          aktualisiere: { app.formeRahmenObjekt(r.id, $0) },
                          ende: { app.sichereRahmen(r.id) })
            }
    }

    private var titelChip: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.dashed").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(farbe)
            if bearbeite {
                TextField("Bereich", text: $entwurf)
                    .textFieldStyle(.plain).font(Design.grotesk(12.5, gewicht: .semibold))
                    .foregroundStyle(.white).focused($fokus).frame(maxWidth: 200)
                    .onSubmit(commit)
            } else {
                Text(r.name).font(Design.grotesk(12.5, gewicht: .semibold)).foregroundStyle(.white)
                    .onTapGesture(count: 2) { starteBearbeiten() }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Design.paneel))   // dunkel → weiße Schrift auch im Hellmodus lesbar
        .overlay(Capsule().strokeBorder(farbe.opacity(0.7), lineWidth: 1))
        .contentShape(Capsule())
        .gesture(ziehGeste)
        .onTapGesture { app.aktiverRahmen = r.id }
        .help("Ziehen verschiebt den Bereich · ⌥ (Option) halten, um ihn an der ganzen Fläche zu fassen")
        .contextMenu {
            Button("Hierher springen") { app.springeZuRahmen(r.id) }
            Button("Umbenennen") { starteBearbeiten() }
            Menu("Farbe") {
                ForEach(0..<Design.objektFarben.count, id: \.self) { i in
                    Button("Farbe \(i + 1)") { app.setzeRahmenFarbe(r.id, i) }
                }
            }
            Divider()
            Button("Bereich löschen", role: .destructive) { app.loescheRahmen(r.id) }
        }
    }

    private var ziehGeste: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Leinwand.raum))
            .onChanged { g in
                if letzteTrans == .zero { app.beginneAktion(); app.aktiverRahmen = r.id }
                let dx = (g.translation.width - letzteTrans.width) / app.zoom
                let dy = (g.translation.height - letzteTrans.height) / app.zoom
                app.verschiebeRahmen(r.id, dx: dx, dy: dy)
                letzteTrans = g.translation
            }
            .onEnded { _ in letzteTrans = .zero; app.sichereRahmen(r.id) }
    }

    private func starteBearbeiten() {
        entwurf = r.name; bearbeite = true
        DispatchQueue.main.async { fokus = true }
    }
    private func commit() { app.benenneRahmen(r.id, entwurf); bearbeite = false }
}

// MARK: - Notiz (Textfeld)

struct NotizAnsicht: View {
    @EnvironmentObject var app: AppModell
    let n: Notiz
    @State private var start: CGPoint?
    @State private var letzteTrans: CGSize = .zero
    @State private var groesseStart: CGSize?
    @State private var bearbeite = false
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    private var markiert: Bool { app.istMarkiert(.notiz(n.id)) }
    private var einzeln: Bool { app.auswahl == .notiz(n.id) }
    private var istZettel: Bool { n.zettel }
    /// Füllfarbe eines Zettels (kräftig, aus Palette/Hex).
    private var zettelFarbe: Color { Design.farbe(index: n.farbe, hex: n.farbhex) }
    private var textFarbe: Color {
        if istZettel { return Color(red: 0.17, green: 0.15, blue: 0.11) }
        // Freier Text/Überschrift: heller Standard (≈Weiß) wäre auf hellem Canvas
        // unsichtbar → dann dunkle Tinte verwenden.
        if !app.istDunkel, n.farbhex == nil, n.farbe == 0 {
            return Color(red: 0.12, green: 0.14, blue: 0.20)
        }
        return Design.notizTextFarbe(farbe: n.farbe, hex: n.farbhex)
    }
    /// Akzent für Rahmen/Griff: beim Zettel die Füllfarbe, sonst die Textfarbe.
    private var akzent: Color { istZettel ? zettelFarbe : textFarbe }
    private var schrift: Font {
        switch n.stil {
        case 2: return .system(size: 34, weight: .bold)      // Überschrift 1
        case 1: return .system(size: 24, weight: .semibold)  // Überschrift 2
        default: return .system(size: 16, weight: .regular)  // Text
        }
    }

    var body: some View {
        inhalt
            .frame(width: n.breite, height: n.hoehe, alignment: .topLeading)
            // Post-it: immer farbig gefüllt. Freier Text: rahmenlos, Rahmen nur bei Auswahl.
            .background(hintergrund)
            .overlay(rand)
            .shadow(color: .black.opacity(istZettel ? 0.34 : ((markiert || bearbeite) ? 0.3 : 0)),
                    radius: istZettel ? 8 : 6, y: istZettel ? 5 : 3)
            .contentShape(Rectangle())
            .overlay {
                if einzeln || bearbeite {
                    EckGriffe(farbe: akzent, verh: nil, minB: 120, minH: 54, groesse: 13,
                              rechteck: { CGRect(x: n.x, y: n.y, width: n.breite, height: n.hoehe) },
                              beginn: { app.beginneAktion() },
                              aktualisiere: { app.formeNotiz(n.id, $0) },
                              ende: { app.sichereNotizRahmen(n.id) })
                }
            }
            .gesture(ziehGeste, including: bearbeite ? .subviews : .all)
            .onTapGesture(count: 2) { starte() }
            .onTapGesture(count: 1) { app.objektGetippt(.notiz(n.id)) }
            .onChange(of: fokus) { _, f in if !f { bearbeite = false } }
            .onAppear { if app.fokusNotiz == n.id { app.fokusNotiz = nil; starte() } }
            .onChange(of: app.auswahl) { _, neu in
                if bearbeite && neu != .notiz(n.id) { bearbeite = false; fokus = false }
            }
            .contextMenu { menue }
    }

    @ViewBuilder private var hintergrund: some View {
        if istZettel {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Design.pastell(zettelFarbe))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((markiert || bearbeite) ? Color.black.opacity(0.38) : Color.clear)
        }
    }

    @ViewBuilder private var rand: some View {
        if istZettel {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(zettelFarbe.opacity(markiert ? 0.95 : 0.55), lineWidth: markiert ? 2.5 : 1)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(akzent, lineWidth: 1.5)
                .opacity((markiert || bearbeite) ? 1 : 0)
        }
    }

    @ViewBuilder private var inhalt: some View {
        if bearbeite {
            TextEditor(text: $entwurf)
                .font(schrift)
                .foregroundStyle(textFarbe)
                .scrollContentBackground(.hidden)
                .focused($fokus)
                .padding(7)
                .onChange(of: entwurf) { _, neu in app.setzeNotizText(n.id, neu) }
        } else {
            Text(n.text.isEmpty ? (istZettel ? "Zettel…" : "Text…") : n.text)
                .font(schrift)
                .foregroundStyle(n.text.isEmpty ? textFarbe.opacity(0.45) : textFarbe)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(9)
        }
    }

    private var ziehGeste: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Leinwand.raum))
            .onChanged { g in
                if app.markierung.count > 1 && app.istMarkiert(.notiz(n.id)) {
                    if letzteTrans == .zero { app.beginneAktion() }
                    let dx = (g.translation.width - letzteTrans.width) / app.zoom
                    let dy = (g.translation.height - letzteTrans.height) / app.zoom
                    app.verschiebeMarkierung(dx: dx, dy: dy)
                    letzteTrans = g.translation
                } else {
                    let s = start ?? CGPoint(x: n.x, y: n.y)
                    if start == nil { app.beginneAktion(); start = s; app.einzelAuswahl(.notiz(n.id)) }
                    let nx = s.x + g.translation.width / app.zoom
                    let ny = s.y + g.translation.height / app.zoom
                    app.verschiebeNotiz(n.id, x: nx, y: ny)
                    app.aktualisiereZiel(CGPoint(x: nx + n.breite / 2, y: ny + n.hoehe / 2))
                }
            }
            .onEnded { _ in
                if letzteTrans != .zero { letzteTrans = .zero; app.sichereMarkierung() }
                else { start = nil; app.sichereNotizRahmen(n.id) }
            }
    }

    @ViewBuilder private var menue: some View {
        Button("Bearbeiten") { starte() }
        Divider()
        Button("Textfeld löschen", role: .destructive) { app.frageLoeschen(.notiz(n.id)) }
    }

    private func starte() {
        entwurf = n.text
        bearbeite = true
        app.einzelAuswahl(.notiz(n.id))
        DispatchQueue.main.async { fokus = true }
    }
}

// MARK: - Verbindungslinien

/// Zeichnet alle Verbindungen in Bildschirm-Koordinaten (nicht im skalierten
/// Container) – dadurch bleiben Kurven und Pfeilspitzen bei jedem Zoom scharf,
/// und die Pfeilspitze hat eine konstante, saubere Größe.
struct VerbindungenCanvas: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        Canvas { ctx, _ in
            let z = app.zoom, sx = app.schwenk.width, sy = app.schwenk.height
            func punkt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * z + sx, y: p.y * z + sy) }
            for v in app.verbindungen {
                guard let g = app.linienGeometrie(v) else { continue }
                let p0 = punkt(g.p0), c1 = punkt(g.c1), c2 = punkt(g.c2), p3 = punkt(g.p3)
                var bogen = Path()
                bogen.move(to: p0)
                bogen.addCurve(to: p3, control1: c1, control2: c2)
                ctx.stroke(bogen, with: .color(Design.neonCyan.opacity(0.78)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // Saubere, dreieckige Pfeilspitze am Ziel (konstante Größe).
                let ang = atan2(p3.y - c2.y, p3.x - c2.x)
                let laenge = 12.0, halbBreite = 6.5
                let nx = -sin(ang), ny = cos(ang)
                let basis = CGPoint(x: p3.x - cos(ang) * laenge, y: p3.y - sin(ang) * laenge)
                var spitze = Path()
                spitze.move(to: p3)
                spitze.addLine(to: CGPoint(x: basis.x + nx * halbBreite, y: basis.y + ny * halbBreite))
                spitze.addLine(to: CGPoint(x: basis.x - nx * halbBreite, y: basis.y - ny * halbBreite))
                spitze.closeSubpath()
                ctx.fill(spitze, with: .color(Design.neonCyan.opacity(0.92)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct VerbindungLinie: View {
    @EnvironmentObject var app: AppModell
    let v: Verbindung

    var body: some View {
        if let g = app.linienGeometrie(v) {
            // Tangente am Ziel (für die Pfeilrichtung): p3 − c2.
            let ang = atan2(g.p3.y - g.c2.y, g.p3.x - g.c2.x)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: g.p0)
                    p.addCurve(to: g.p3, control1: g.c1, control2: g.c2)
                }
                .stroke(Design.neonCyan.opacity(0.75),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                // Pfeilspitze dockt an der Kante des Zielobjekts an.
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.neonCyan.opacity(0.9))
                    .rotationEffect(.radians(ang))
                    .offset(x: g.p3.x - cos(ang) * 6 - 6.5, y: g.p3.y - sin(ang) * 6 - 6.5)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Mittelpunkt einer Verbindung: zeigt (optional) ihre Beschriftung und bietet
/// beim Überfahren Bearbeiten und Entfernen. Doppelklick beschriftet.
struct VerbindungPunkt: View {
    @EnvironmentObject var app: AppModell
    let v: Verbindung
    @State private var hover = false
    @State private var bearbeite = false
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    var body: some View {
        if let g = app.linienGeometrie(v) {
            // 0×0-Anker am Mittelpunkt → Overlay zentriert die Steuerung dort.
            Color.clear.frame(width: 0, height: 0)
                .offset(x: g.mitte.x, y: g.mitte.y)
                .overlay { steuerung }
        }
    }

    @ViewBuilder private var steuerung: some View {
        if bearbeite {
            TextField("Beschriftung", text: $entwurf)
                .textFieldStyle(.plain).font(Design.grotesk(11, gewicht: .semibold))
                .foregroundStyle(.white).frame(width: 118).focused($fokus)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(Design.paneel))
                .overlay(Capsule().strokeBorder(Design.neonCyan, lineWidth: 1))
                .onSubmit(sichern)
                .onKeyPress(.escape) { bearbeite = false; return .handled }
                .onChange(of: fokus) { _, f in if !f { sichern() } }
        } else {
            HStack(spacing: 5) {
                if !v.label.isEmpty {
                    Text(v.label).font(Design.grotesk(10.5, gewicht: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                } else if !hover {
                    Circle().fill(Design.neonCyan).frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                }
                if hover {
                    Image(systemName: v.label.isEmpty ? "text.badge.plus" : "pencil")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .onTapGesture { starte() }
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .onTapGesture { app.loescheVerbindung(v.id) }
                }
            }
            .padding(.horizontal, v.label.isEmpty && !hover ? 0 : 7)
            .padding(.vertical, v.label.isEmpty && !hover ? 0 : 4)
            .background {
                if !(v.label.isEmpty && !hover) {
                    Capsule().fill(hover ? Design.paneel : Design.neonCyan.opacity(0.9))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(count: 2) { starte() }
            .help(v.label.isEmpty ? "Doppelklick beschriftet · ✕ entfernt" : "Doppelklick bearbeitet · ✕ entfernt")
        }
    }

    private func starte() {
        entwurf = v.label
        bearbeite = true
        DispatchQueue.main.async { fokus = true }
    }
    private func sichern() {
        app.setzeVerbindungLabel(v.id, entwurf)
        bearbeite = false
    }
}

// MARK: - Ablegeziel (Drag & Drop von Dateien)

struct AblegeZiel: DropDelegate {
    let app: AppModell
    let nachLeinwand: (CGPoint) -> CGPoint

    init(app: AppModell, nachLeinwand: @escaping (CGPoint) -> CGPoint) {
        self.app = app
        self.nachLeinwand = nachLeinwand
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL, UTType.url, UTType.plainText])
    }

    func performDrop(info: DropInfo) -> Bool {
        // Dateien/Ordner und Web-Links getrennt sammeln – ein Datei-Objekt meldet
        // beide Typen, deshalb wandern Nicht-Datei-URLs in die Weblink-Liste.
        let dateiAnbieter = info.itemProviders(for: [UTType.fileURL])
        let urlAnbieter = info.itemProviders(for: [UTType.url])
        let textAnbieter = info.itemProviders(for: [UTType.plainText])
        guard !dateiAnbieter.isEmpty || !urlAnbieter.isEmpty || !textAnbieter.isEmpty else { return false }
        let basis = nachLeinwand(info.location)

        let dateien = URLSammler()
        let links = URLSammler()
        let texte = TextSammler()
        let gruppe = DispatchGroup()
        for p in dateiAnbieter {
            gruppe.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { dateien.fuege(url) }
                gruppe.leave()
            }
        }
        for p in urlAnbieter {
            gruppe.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, !url.isFileURL { links.fuege(url) }
                gruppe.leave()
            }
        }
        for p in textAnbieter {
            gruppe.enter()
            _ = p.loadObject(ofClass: NSString.self) { s, _ in
                if let s = s as? String { texte.fuege(s) }
                gruppe.leave()
            }
        }
        gruppe.notify(queue: .main) {
            let urls = dateien.alle
            if !urls.isEmpty {
                let punkte = urls.enumerated().map { (i, _) in
                    CGPoint(x: basis.x + Double(i) * 26, y: basis.y + Double(i) * 26)
                }
                app.importiere(urls, an: punkte)
            }
            for (i, link) in links.alle.enumerated() {
                app.legeWeblinkAb(link.absoluteString,
                                  an: CGPoint(x: basis.x + Double(urls.count + i) * 26,
                                              y: basis.y + Double(urls.count + i) * 26))
            }
            // Reinen Text nur als Notiz ablegen, wenn keine Datei/kein Link dabei war
            // (ein gezogener Link liefert zusätzlich seinen Text mit).
            if urls.isEmpty, links.alle.isEmpty {
                let t = texte.alle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { app.erstelleNotizMitText(t, an: basis) }
            }
        }
        return true
    }
}

private final class TextSammler {
    private let sperre = NSLock()
    private var teile: [String] = []
    func fuege(_ s: String) { sperre.lock(); teile.append(s); sperre.unlock() }
    var alle: String { sperre.lock(); defer { sperre.unlock() }; return teile.joined(separator: "\n") }
}

private final class URLSammler {
    private let sperre = NSLock()
    private var liste: [URL] = []
    func fuege(_ u: URL) { sperre.lock(); liste.append(u); sperre.unlock() }
    var alle: [URL] { sperre.lock(); defer { sperre.unlock() }; return liste }
}
