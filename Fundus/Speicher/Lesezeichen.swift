import Foundation

/// Datei-Lesezeichen (Bookmark): merkt sich eine Datei/einen Ordner so, dass die
/// Referenz ein Verschieben oder Umbenennen übersteht (das System verfolgt die
/// Datei über ihre Kennung, nicht nur über den Pfad). Rein lokal, kein Netz.
enum Lesezeichen {

    /// Bookmark für eine Datei-URL erzeugen (als base64-Text zum Speichern).
    static func erzeuge(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return nil }
        return data.base64EncodedString()
    }

    /// Bookmark auflösen → aktueller Ort der Datei (auch nach Verschieben/Umbenennen).
    /// `veraltet` = true, wenn das Bookmark erneuert werden sollte.
    static func aufloese(_ base64: String) -> (url: URL, veraltet: Bool)? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        var veraltet = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [],
                                 relativeTo: nil, bookmarkDataIsStale: &veraltet)
        else { return nil }
        return (url, veraltet)
    }
}
