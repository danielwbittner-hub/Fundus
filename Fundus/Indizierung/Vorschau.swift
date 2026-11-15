import Foundation
import AppKit
import QuickLookThumbnailing
import PDFKit
import ImageIO

/// Erzeugt ein Vorschaubild. Reihenfolge je nach Typ:
///  • INDD: gleichnamige PDF daneben (scharf!) → QuickLook → eingebettete Bitmap.
///  • Affinity (.afdesign/.afphoto/.afpub): QuickLook → eingebettete Vorschau-Bitmap.
///  • alle anderen: QuickLook (PDF, Bilder, Office …).
/// Ablage als PNG im Ordner `.vorschau/` neben der Datenbank.
enum Vorschau {
    static func erzeuge(fuer url: URL, id: Int, ordner: URL) async -> String? {
        let ext = url.pathExtension.lowercased()

        // INDD: eine gleichnamige PDF daneben ist die beste, gestochen scharfe
        // Vorschauquelle (QuickLook rendert INDD auf vielen Macs gar nicht).
        if ext == "indd", let pdf = sidecarPDF(url),
           let name = pdfVorschau(pdf, id: id, ordner: ordner) {
            return name
        }

        // QuickLook für alle Typen (PDF, Bilder, Office, teils INDD/Affinity).
        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 512, height: 640),
            scale: 2,
            representationTypes: .thumbnail
        )
        // Mit echtem Zeitlimit: QuickLook hat keine Cancel-API und kann bei INDD
        // dauerhaft hängen. Darum kehrt die Funktion nach 15 s selbst mit nil zurück
        // (genau-einmal-Resume per Lock), ohne auf den QL-Callback zu warten – sonst
        // bliebe ein Indizier-/Drossel-Platz dauerhaft belegt.
        let rep: QLThumbnailRepresentation? = await withCheckedContinuation { fort in
            let sperre = NSLock()
            var fertig = false
            func liefere(_ r: QLThumbnailRepresentation?) {
                sperre.lock(); let erste = !fertig; fertig = true; sperre.unlock()
                if erste { fort.resume(returning: r) }
            }
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { r, _ in liefere(r) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { liefere(nil) }
        }
        if let cg = rep?.cgImage,
           let daten = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            let name = "\(id).png"
            if (try? daten.write(to: ordner.appendingPathComponent(name))) != nil { return name }
        }

        // INDD / Affinity ohne QuickLook → eingebettete Vorschau-Bitmap (best effort).
        if ext == "indd" || ext == "afdesign" || ext == "afphoto" || ext == "afpub",
           let name = eingebetteteVorschau(url: url, id: id, ordner: ordner) {
            return name
        }
        return nil
    }

    /// Gleichnamige PDF neben einer Datei (z. B. der Export einer INDD).
    private static func sidecarPDF(_ url: URL) -> URL? {
        let pdf = url.deletingPathExtension().appendingPathExtension("pdf")
        return FileManager.default.fileExists(atPath: pdf.path) ? pdf : nil
    }

    /// Erste Seite einer PDF als PNG rendern (scharf, begrenzt auf ~1600 px Kante).
    private static func pdfVorschau(_ pdf: URL, id: Int, ordner: URL) -> String? {
        guard let doc = PDFDocument(url: pdf), let page = doc.page(at: 0) else { return nil }
        let box = page.bounds(for: .cropBox)
        guard box.width > 1, box.height > 1 else { return nil }
        let skala = min(1600 / max(box.width, box.height), 4)
        let groesse = CGSize(width: box.width * skala, height: box.height * skala)
        let bild = page.thumbnail(of: groesse, for: .cropBox)
        guard let tiff = bild.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let name = "\(id).png"
        return (try? png.write(to: ordner.appendingPathComponent(name))) != nil ? name : nil
    }

    /// Eingebettete Seitenvorschau/Bitmap aus einer Datei ziehen (INDD/Affinity):
    /// die flächenmäßig größte brauchbare JPEG/PNG im Datenstrom als PNG ablegen.
    private static func eingebetteteVorschau(url: URL, id: Int, ordner: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let rep = groessteBitmap(data),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = "\(id).png"
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        do { try png.write(to: ordner.appendingPathComponent(name)); return name }
        catch { return nil }
    }

    /// Durchsucht die Datei nach JPEG-/PNG-Signaturen und gibt die flächenmäßig
    /// größte brauchbare Bitmap (≥200×200 px) zurück. Wichtig: pro Kandidat wird
    /// NUR ein kleines Fenster für die Maß-Prüfung gelesen (ohne Volldekodierung,
    /// ohne den gesamten Dateirest zu kopieren); erst die Siegerin wird dekodiert.
    private static func groessteBitmap(_ data: Data) -> NSBitmapImageRep? {
        var starts: [Int] = []
        data.withUnsafeBytes { roh in
            guard let p = roh.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let n = roh.count
            var i = 0
            while i + 8 < n && starts.count < 300 {
                if p[i] == 0xFF, p[i + 1] == 0xD8, p[i + 2] == 0xFF { starts.append(i); i += 3 }
                else if p[i] == 0x89, p[i + 1] == 0x50, p[i + 2] == 0x4E, p[i + 3] == 0x47 {
                    starts.append(i); i += 8
                } else { i += 1 }
            }
        }
        let probe = 4_000_000, fenster = 64_000_000   // Probe groß genug für JPEG-SOF hinter EXIF/ICC
        var besteOffset: Int?
        var besteFlaeche = 0
        for s in starts {
            autoreleasepool {
                let sub = data.subdata(in: s..<min(data.count, s + probe))
                guard let quelle = CGImageSourceCreateWithData(sub as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(quelle, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int,
                      let h = props[kCGImagePropertyPixelHeight] as? Int,
                      w >= 200, h >= 200 else { return }
                if w * h > besteFlaeche { besteFlaeche = w * h; besteOffset = s }
            }
        }
        guard let s = besteOffset else { return nil }
        let sub = data.subdata(in: s..<min(data.count, s + fenster))
        return NSBitmapImageRep(data: sub)
    }
}
