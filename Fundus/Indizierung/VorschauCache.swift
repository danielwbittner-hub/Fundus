import AppKit

/// Hält dekodierte Vorschaubilder und Datei-Icons im Speicher, damit sie beim
/// Rendern (Hover, Ziehen, Canvas-Wechsel) nicht jedes Mal neu von der Platte
/// gelesen und dekodiert werden müssen.
final class VorschauCache {
    static let shared = VorschauCache()

    private let bilder = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()

    private init() {
        bilder.countLimit = 500
    }

    /// Vorschaubild zu einem Dateinamen im `.vorschau/`-Ordner – aus dem Cache,
    /// sonst einmalig laden und merken.
    func bild(ordner: URL, name: String) -> NSImage? {
        let key = name as NSString
        if let vorhanden = bilder.object(forKey: key) { return vorhanden }
        guard let geladen = NSImage(contentsOf: ordner.appendingPathComponent(name)) else { return nil }
        bilder.setObject(geladen, forKey: key)
        return geladen
    }

    /// System-Icon zu einer Datei – pro Endung gecacht (gleiche Typen teilen das Icon).
    func icon(pfad: String) -> NSImage {
        let endung = (pfad as NSString).pathExtension.lowercased()
        let key = (endung.isEmpty ? "∅:" + pfad : "." + endung) as NSString
        if let vorhanden = icons.object(forKey: key) { return vorhanden }
        let erzeugt = NSWorkspace.shared.icon(forFile: pfad)
        icons.setObject(erzeugt, forKey: key)
        return erzeugt
    }

    /// Nach dem Neu-Erzeugen einer Vorschau den alten Cache-Eintrag verwerfen.
    func verwerfe(name: String) {
        bilder.removeObject(forKey: name as NSString)
    }
}
