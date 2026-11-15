import Foundation
import AppKit
import PDFKit
import Vision

/// Holt durchsuchbaren Text aus einer Datei – je nach Typ. Läuft im Hintergrund.
enum Textextraktion {
    /// `ocr` = gescannte PDFs / Bilder zusätzlich per Texterkennung erfassen.
    static func text(fuer url: URL, kategorie: Kategorie, idmlQuelle: String?, ocr: Bool) -> String {
        switch kategorie {
        case .pdf:       return pdf(url, ocr: ocr)
        case .text:      return klartext(url)
        case .idml:      return IDML.text(idmlURL: url)
        case .indesign:  return idmlQuelle.map { IDML.text(idmlURL: URL(fileURLWithPath: $0)) } ?? ""
        case .office:    return office(url)
        case .bild:
            if url.pathExtension.lowercased() == "svg" { return svgText(url) }
            return ocr ? bildOCR(url) : ""
        case .vektor:    return "" // AI/EPS: kein zuverlässiger Textzugriff
        case .sonstiges: return ""
        case .ordnerExtern, .weblink: return "" // werden separat im AppModell indiziert
        }
    }

    // MARK: Begrenztes Lesen (gegen riesige/entpackte Dateien → OOM)

    /// Liest höchstens `maxBytes` Bytes als Text (UTF-8, Fallback Latin-1).
    private static func liesText(_ url: URL, maxBytes: Int) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let d = (try? fh.read(upToCount: maxBytes)) ?? Data()
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }

    /// Dateigröße (0, falls unbekannt).
    private static func groesse(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    // MARK: SVG (Text aus der XML)

    private static func svgText(_ url: URL) -> String {
        guard var s = liesText(url, maxBytes: 12_000_000) else { return "" }
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&[a-zA-Z#0-9]+;", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: PDF (+ OCR bei gescannten Seiten)

    private static func pdf(_ url: URL, ocr: Bool) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        var teile: [String] = []
        for i in 0..<doc.pageCount {
            if let s = doc.page(at: i)?.string { teile.append(s) }
        }
        let text = teile.joined(separator: "\n")
        let hatText = text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 16
        if hatText || !ocr { return text }

        // Kaum eingebetteter Text → vermutlich gescannt: bis zu 25 Seiten per OCR.
        var erkannt: [String] = []
        let max = min(doc.pageCount, 25)
        for i in 0..<max {
            guard let seite = doc.page(at: i), let bild = seiteAlsBild(seite, skala: 2) else { continue }
            erkannt.append(OCRText(bild))
        }
        let ocrText = erkannt.joined(separator: "\n")
        return ocrText.isEmpty ? text : ocrText
    }

    private static func seiteAlsBild(_ seite: PDFPage, skala rohSkala: CGFloat) -> CGImage? {
        let box = seite.bounds(for: .mediaBox)
        guard box.width > 1, box.height > 1 else { return nil }
        // Längste Kante deckeln (Großformat-PDF würde sonst GB an RAM belegen → Crash).
        let maxKante: CGFloat = 4000
        let skala = min(rohSkala, maxKante / max(box.width, box.height))
        let w = max(1, Int(box.width * skala)), h = max(1, Int(box.height * skala))
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: skala, y: skala)
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        seite.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    // MARK: Bild-OCR

    private static func bildOCR(_ url: URL) -> String {
        guard let quelle = CGImageSourceCreateWithURL(url as CFURL, nil),
              let bild = CGImageSourceCreateImageAtIndex(quelle, 0, nil) else { return "" }
        return OCRText(bild)
    }

    private static func OCRText(_ bild: CGImage) -> String {
        let anfrage = VNRecognizeTextRequest()
        anfrage.recognitionLevel = .accurate
        anfrage.usesLanguageCorrection = true
        anfrage.recognitionLanguages = ["de-DE", "en-US"]
        let handler = VNImageRequestHandler(cgImage: bild, options: [:])
        try? handler.perform([anfrage])
        let zeilen = (anfrage.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return zeilen.joined(separator: "\n")
    }

    // MARK: Klartext / RTF / HTML

    private static func klartext(_ url: URL) -> String {
        let endung = url.pathExtension.lowercased()
        if endung == "rtf" {
            // RTF nur bei vernünftiger Größe über die (teure) AttributedString-API.
            if groesse(url) <= 20_000_000,
               let s = try? NSAttributedString(
                url: url, options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil) { return s.string }
            return ""
        }
        var roh = liesText(url, maxBytes: 20_000_000) ?? ""
        if endung == "html" || endung == "htm" {
            roh = roh.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }
        return roh
    }

    // MARK: Office (best-effort: XML entpacken und Tags entfernen)

    private static func office(_ url: URL) -> String {
        let eintraege: [String]
        switch url.pathExtension.lowercased() {
        case "docx": eintraege = ["word/document.xml"]
        case "pptx": eintraege = ["ppt/slides/slide*.xml", "ppt/notesSlides/notesSlide*.xml"]
        case "xlsx": eintraege = ["xl/sharedStrings.xml"]
        default: return ""
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fundus-office-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", url.path] + eintraege + ["-d", tmp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard Prozesslauf.fuehre(p, frist: 20) else { return "" }

        guard let alle = FileManager.default.enumerator(at: tmp, includingPropertiesForKeys: nil)
        else { return "" }
        var teile: [String] = []
        for fall in alle {
            guard let d = fall as? URL, d.pathExtension.lowercased() == "xml",
                  groesse(d) <= 60_000_000,                      // entpackte XML deckeln (Zip-Bombe)
                  let roh = liesText(d, maxBytes: 60_000_000) else { continue }
            let text = roh
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            teile.append(text)
        }
        return teile.joined(separator: "\n")
    }
}
