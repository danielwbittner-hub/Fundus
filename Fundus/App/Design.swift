import SwiftUI

/// Zentrale Gestaltung – ein ruhig-futuristischer Look: dunkle Leinwand mit
/// feinem Raster, Neon-Akzent (Cyan→Violett), Karten als schwebende Paneele.
enum Design {
    // Akzent
    static let akzent = Color(red: 0.45, green: 0.52, blue: 1.0)
    static let neonCyan = Color(red: 0.18, green: 0.90, blue: 0.94)
    static let neonViolett = Color(red: 0.54, green: 0.42, blue: 1.0)
    static let neonFuchsia = Color(red: 0.88, green: 0.29, blue: 0.94)

    static var neon: LinearGradient {
        LinearGradient(colors: [neonCyan, neonViolett, neonFuchsia],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Flächen
    static let papier = Color(nsColor: .windowBackgroundColor)
    static let karte = Color(nsColor: .controlBackgroundColor)
    static let vorschauGrund = Color(red: 0.94, green: 0.95, blue: 0.97)
    static let tinte = Color(nsColor: .labelColor)
    static let gedaempft = Color(nsColor: .secondaryLabelColor)
    static let rahmen = Color.white.opacity(0.10)

    /// Hintergrund der schwebenden Bedien-Paneele (bewusst dunkel, damit weiße
    /// Symbole/Schrift gut lesbar sind – unabhängig vom System-Erscheinungsbild).
    static let paneel = Color(red: 0.07, green: 0.09, blue: 0.15).opacity(0.93)
    /// Symbole & Texte in den Paneelen: helles Grau statt hartem Weiß.
    static let paneelInhalt = Color.white.opacity(0.78)

    /// Dunkler Leinwand-Verlauf (der „Space"-Look).
    static var leinwandVerlauf: LinearGradient { leinwandVerlauf(dunkel: true) }

    /// Leinwand-Verlauf je nach Erscheinungsbild (dunkler „Space" oder helles Papier).
    static func leinwandVerlauf(dunkel: Bool) -> LinearGradient {
        if dunkel {
            return LinearGradient(colors: [
                Color(red: 0.05, green: 0.07, blue: 0.13),
                Color(red: 0.06, green: 0.09, blue: 0.19),
                Color(red: 0.04, green: 0.05, blue: 0.11)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [
                Color(red: 0.93, green: 0.95, blue: 0.98),
                Color(red: 0.88, green: 0.91, blue: 0.96),
                Color(red: 0.90, green: 0.92, blue: 0.97)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    static let rasterPunkt = Color(red: 0.5, green: 0.6, blue: 1.0)
    /// Rasterpunkt-Farbe je nach Erscheinungsbild.
    static func rasterPunkt(dunkel: Bool) -> Color {
        dunkel ? rasterPunkt : Color(red: 0.25, green: 0.33, blue: 0.55)
    }

    /// Farbpalette für Ordner & Notizen (Index wird gespeichert).
    static let objektFarben: [Color] = [
        neonViolett,
        neonCyan,
        Color(red: 0.30, green: 0.85, blue: 0.52),   // Grün
        Color(red: 1.00, green: 0.74, blue: 0.24),   // Bernstein
        neonFuchsia
    ]
    static func objektFarbe(_ i: Int) -> Color {
        let n = objektFarben.count
        return objektFarben[((i % n) + n) % n]
    }

    /// Helle Pastelltöne für Text/Überschriften, die sich vom dunklen Canvas
    /// absetzen. Index 0 ist (fast) Weiß = Standard.
    static let textPastell: [Color] = [
        Color(red: 0.96, green: 0.97, blue: 0.99),   // Weiß
        Color(red: 0.62, green: 0.90, blue: 0.95),   // Pastell-Cyan
        Color(red: 0.70, green: 0.93, blue: 0.78),   // Pastell-Mint
        Color(red: 0.99, green: 0.90, blue: 0.62),   // Pastell-Gelb
        Color(red: 0.99, green: 0.74, blue: 0.83),   // Pastell-Rosa
        Color(red: 0.82, green: 0.76, blue: 0.99)    // Pastell-Flieder
    ]
    static func textPastellFarbe(_ i: Int) -> Color {
        let n = textPastell.count
        return textPastell[((i % n) + n) % n]
    }

    /// Textfarbe eines freien Textfelds/Überschrift: eigener Hex-Wert hat Vorrang,
    /// sonst heller Pastellton (Index 0 ≈ Weiß = Standard).
    static func notizTextFarbe(farbe: Int, hex: String?) -> Color {
        if let h = hex, !h.isEmpty { return Color(hex: h) }
        return textPastellFarbe(farbe)
    }

    /// Farbe eines Objekts auflösen: eigener Hex-Wert hat Vorrang vor der Palette.
    static func farbe(index: Int, hex: String?) -> Color {
        if let h = hex, !h.isEmpty { return Color(hex: h) }
        return objektFarbe(index)
    }

    /// Weiche Pastellvariante (zur Hälfte Richtung Weiß) – für Post-it-Flächen.
    static func pastell(_ c: Color) -> Color {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .gray
        func m(_ v: CGFloat) -> Double { Double(v) * 0.42 + 0.58 }
        return Color(red: m(ns.redComponent), green: m(ns.greenComponent), blue: m(ns.blueComponent))
    }

    static func serife(_ groesse: CGFloat, gewicht: Font.Weight = .regular) -> Font {
        .system(size: groesse, weight: gewicht, design: .serif)
    }
    static func grotesk(_ groesse: CGFloat, gewicht: Font.Weight = .regular) -> Font {
        .system(size: groesse, weight: gewicht)
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        if s.count == 6 {
            self = Color(red: Double((v >> 16) & 0xff) / 255,
                         green: Double((v >> 8) & 0xff) / 255,
                         blue: Double(v & 0xff) / 255)
        } else {
            self = Color(red: 0.5, green: 0.5, blue: 1.0)
        }
    }

    /// „#RRGGBB" im sRGB-Raum.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}

/// Bewegliches Punkt-Raster, das Schwenk & Zoom der Leinwand mitmacht.
struct RasterHintergrund: View {
    let zoom: Double
    let schwenk: CGSize
    var dunkel: Bool = true

    var body: some View {
        Canvas { ctx, size in
            let basis = 42.0
            let s = basis * zoom
            guard s > 7 else { return }
            let ox = schwenk.width.truncatingRemainder(dividingBy: s)
            let oy = schwenk.height.truncatingRemainder(dividingBy: s)
            let r = max(1.0, 1.4 * zoom)
            let schattierung = GraphicsContext.Shading.color(Design.rasterPunkt(dunkel: dunkel).opacity(dunkel ? 0.10 : 0.16))
            // Alle Punkte in EINEN Pfad sammeln und einmal füllen (statt pro Punkt).
            var punkte = Path()
            var y = oy - s
            while y < size.height + s {
                var x = ox - s
                while x < size.width + s {
                    punkte.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    x += s
                }
                y += s
            }
            ctx.fill(punkte, with: schattierung)
        }
        .allowsHitTesting(false)
    }
}
