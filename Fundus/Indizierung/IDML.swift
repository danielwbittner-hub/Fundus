import Foundation

/// Liest den Text aus einer IDML-Datei. IDML ist ein ZIP mit XML; die Texte
/// liegen in `Stories/*.xml` als Story → ParagraphStyleRange → CharacterStyleRange
/// → Content. Nachgebaut aus dem JS-Parser des IDML-Editor-Projekts.
enum IDML {
    static func text(idmlURL: URL) -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("fundus-idml-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Nur den Stories-Ordner entpacken.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", idmlURL.path, "Stories/*", "-d", tmp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard Prozesslauf.fuehre(p, frist: 20) else { return "" }

        let storiesDir = tmp.appendingPathComponent("Stories")
        guard let dateien = try? FileManager.default.contentsOfDirectory(
            at: storiesDir, includingPropertiesForKeys: nil) else { return "" }

        var teile: [String] = []
        for d in dateien where d.pathExtension.lowercased() == "xml" {
            // Entpackte Story-XML deckeln (kaputte/aufgeblähte IDML → OOM).
            let bytes = (try? d.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard bytes <= 60_000_000, let daten = try? Data(contentsOf: d) else { continue }
            let parser = XMLParser(data: daten)
            let leser = StoryLeser()
            parser.delegate = leser
            parser.parse()
            let t = leser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { teile.append(t) }
        }
        return teile.joined(separator: "\n\n")
    }
}

/// Sammelt den Text einer einzelnen Story-XML.
private final class StoryLeser: NSObject, XMLParserDelegate {
    private(set) var text = ""
    private var imInhalt = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "Content": imInhalt = true
        case "Br": text += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if imInhalt { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Content": imInhalt = false
        case "ParagraphStyleRange": text += "\n"   // Absatzende
        default: break
        }
    }
}
