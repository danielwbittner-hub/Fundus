import SwiftUI
import AppKit

/// Statische Darstellung der ganzen Leinwand (ohne Bedien-Griffe) für den Export.
struct ExportLeinwand: View {
    @EnvironmentObject var app: AppModell
    let rect: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Design.leinwandVerlauf
            ZStack(alignment: .topLeading) {
                // Bereiche hinten (schlichte Rahmen, keine Griffe)
                ForEach(app.rahmenListe) { r in bereich(r).offset(x: r.x, y: r.y) }
                // Verbindungen
                ForEach(app.verbindungen) { v in VerbindungLinie(v: v) }
                // Mappen
                ForEach(app.ordnerListe) { o in OrdnerAnsicht(o: o).offset(x: o.x, y: o.y) }
                // Karten
                ForEach(app.eintraege.filter { !app.istVerborgen($0) }) { e in
                    KarteAnsicht(e: e)
                        .frame(width: e.breite, height: e.hoehe, alignment: .topLeading)
                        .offset(x: e.x, y: e.y)
                }
                // Notizen vorne
                ForEach(app.notizen.filter { !app.istVerborgenN($0) }) { n in
                    NotizAnsicht(n: n)
                        .frame(width: n.breite, height: n.hoehe, alignment: .topLeading)
                        .offset(x: n.x, y: n.y)
                }
                // Verbindungs-Beschriftungen (statisch, am Mittelpunkt)
                ForEach(app.verbindungen) { v in
                    if !v.label.isEmpty, let g = app.linienGeometrie(v) {
                        Color.clear.frame(width: 0, height: 0)
                            .offset(x: g.mitte.x, y: g.mitte.y)
                            .overlay {
                                Text(v.label).font(Design.grotesk(10.5, gewicht: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(Capsule().fill(Design.paneel))
                                    .overlay(Capsule().strokeBorder(Design.neonCyan.opacity(0.6), lineWidth: 0.5))
                            }
                    }
                }
            }
            .frame(width: 1, height: 1, alignment: .topLeading)
            .offset(x: -rect.minX, y: -rect.minY)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
    }

    private func bereich(_ r: Rahmen) -> some View {
        let farbe = Design.objektFarbe(r.farbe)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(farbe.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(farbe.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [11, 8])))
            .frame(width: r.breite, height: r.hoehe)
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.dashed").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(farbe)
                    Text(r.name).font(Design.grotesk(12.5, gewicht: .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.42)))
                .padding(10)
            }
    }
}

/// Rendert die Export-Ansicht zu PNG- bzw. PDF-Daten.
enum LeinwandExport {
    @MainActor static func bild(_ app: AppModell, rect: CGRect, skala: CGFloat) -> Data? {
        let r = ImageRenderer(content: ExportLeinwand(rect: rect).environmentObject(app))
        r.scale = skala
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    @MainActor static func pdf(_ app: AppModell, rect: CGRect) -> Data? {
        let r = ImageRenderer(content: ExportLeinwand(rect: rect).environmentObject(app))
        let daten = NSMutableData()
        r.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: daten as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return daten.isEmpty ? nil : (daten as Data)
    }
}
