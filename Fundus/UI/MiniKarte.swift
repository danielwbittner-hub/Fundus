import SwiftUI

/// Mini-Karte unten rechts: Überblick über alle Objekte der Leinwand mit dem
/// aktuell sichtbaren Ausschnitt. Klick/Ziehen schwenkt die Kamera.
struct MiniKarte: View {
    @EnvironmentObject var app: AppModell

    private let feldB: CGFloat = 196
    private let feldHMax: CGFloat = 150

    /// Umschließendes Rechteck aller Objekte (mit etwas Rand).
    private var inhalt: CGRect? { app.inhaltRechteck()?.insetBy(dx: -40, dy: -40) }

    var body: some View {
        if app.zeigeMiniKarte {
            if let inhalt, inhalt.width > 1, inhalt.height > 1 {
                let s = min(feldB / inhalt.width, feldHMax / inhalt.height)
                let b = inhalt.width * s
                let h = inhalt.height * s
                karte(inhalt: inhalt, skala: s, breite: b, hoehe: h)
            } else {
                knopfNurEin
            }
        } else {
            knopfNurEin
        }
    }

    private func karte(inhalt: CGRect, skala s: CGFloat, breite b: CGFloat, hoehe h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            kopf
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                // Objekte
                ForEach(app.rahmenListe) { r in kachel(r.x, r.y, r.breite, r.hoehe, inhalt, s, Design.objektFarbe(r.farbe).opacity(0.5), rand: true) }
                ForEach(app.ordnerListe) { o in kachel(o.x, o.y, o.breite, o.eingeklappt ? 46 : o.hoehe, inhalt, s, Design.farbe(index: o.farbe, hex: o.farbhex).opacity(0.55)) }
                ForEach(app.eintraege.filter { !app.istVerborgen($0) }) { e in kachel(e.x, e.y, e.breite, e.hoehe, inhalt, s, Design.akzent) }
                ForEach(app.notizen.filter { !app.istVerborgenN($0) }) { n in kachel(n.x, n.y, n.breite, n.hoehe, inhalt, s, Design.neonCyan.opacity(0.8)) }
                // Sichtbarer Ausschnitt
                sichtfenster(inhalt, s)
            }
            .frame(width: b, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let p = CGPoint(x: inhalt.minX + g.location.x / s, y: inhalt.minY + g.location.y / s)
                        app.zentriereLeinwand(p)
                    }
            )
        }
        .frame(width: max(b, 150), alignment: .leading)   // nicht gierig volle Breite ziehen
        .environment(\.colorScheme, .dark)
        .padding(9)
        .background(Design.paneel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    private var kopf: some View {
        HStack(spacing: 6) {
            Image(systemName: "map").font(.system(size: 10, weight: .semibold)).foregroundStyle(Design.neon)
            Text("Übersicht").font(Design.grotesk(11, gewicht: .semibold)).foregroundStyle(Design.paneelInhalt)
            Spacer(minLength: 8)
            Button { app.zeigeMiniKarte = false } label: {
                Image(systemName: "chevron.down.right.and.chevron.up.left").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Design.paneelInhalt)
            }.buttonStyle(.plain).help("Mini-Karte ausblenden")
        }
    }

    /// Eingeklappt: nur ein kleiner Knopf zum Wiedereinblenden.
    private var knopfNurEin: some View {
        Button { app.zeigeMiniKarte = true } label: {
            Image(systemName: "map.fill").font(.system(size: 13))
                .foregroundStyle(Design.paneelInhalt).frame(width: 34, height: 30)
                .background(Design.paneel, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        }
        .buttonStyle(.plain).help("Mini-Karte einblenden")
    }

    private func kachel(_ x: Double, _ y: Double, _ bw: Double, _ bh: Double,
                        _ inhalt: CGRect, _ s: CGFloat, _ farbe: Color, rand: Bool = false) -> some View {
        let w = max(2, bw * s), hh = max(2, bh * s)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(rand ? Color.clear : farbe)
            .overlay(rand ? RoundedRectangle(cornerRadius: 1.5).strokeBorder(farbe, lineWidth: 0.8) : nil)
            .frame(width: w, height: hh)
            .offset(x: (x - inhalt.minX) * s, y: (y - inhalt.minY) * s)
    }

    /// Rechteck des aktuell sichtbaren Ausschnitts (Bildschirm → Leinwand → Mini).
    private func sichtfenster(_ inhalt: CGRect, _ s: CGFloat) -> some View {
        let groesse = app.leinwandGroesse
        let z = app.zoom
        let vx = (0 - app.schwenk.width) / z
        let vy = (0 - app.schwenk.height) / z
        let vw = groesse.width / z
        let vh = groesse.height / z
        return RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Design.neonCyan, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: 2).fill(Design.neonCyan.opacity(0.10)))
            .frame(width: max(6, vw * s), height: max(6, vh * s))
            .offset(x: (vx - inhalt.minX) * s, y: (vy - inhalt.minY) * s)
            .allowsHitTesting(false)
    }
}
