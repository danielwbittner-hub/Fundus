import Foundation
import AppKit

/// Holt Titel und Favicon einer (vom Nutzer eingegebenen) Website. Läuft im
/// Hintergrund; bricht großzügig ab, wenn etwas nicht klappt.
enum WebErfassung {

    static func lade(_ adresse: String) async -> (titel: String?, favicon: Data?) {
        guard let url = URL(string: adresse), let host = url.host else { return (nil, nil) }
        guard let html = await hole(url) else {
            // Trotzdem Standard-Favicon versuchen.
            let fav = await holeDaten(URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico"))
            return (nil, fav)
        }
        let titel = extrahiereTitel(html)
        let favURL = faviconAdresse(html, basis: url)
        var favicon = await holeDaten(favURL)
        if favicon == nil {
            favicon = await holeDaten(URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico"))
        }
        return (titel, favicon)
    }

    /// Prüft, ob eine Adresse erreichbar ist (für den Gesundheits-Check). Erst
    /// HEAD, bei Ablehnung GET (mit kleinem Deckel). Netzwerkfehler/4xx/5xx → nein.
    static func erreichbar(_ adresse: String) async -> Bool {
        guard let url = URL(string: adresse), istWeb(url) else { return false }
        var kopf = anfrage(url)
        kopf.httpMethod = "HEAD"
        if let (_, resp) = try? await URLSession.shared.data(for: kopf),
           let code = (resp as? HTTPURLResponse)?.statusCode {
            if (200..<400).contains(code) { return true }
            if code != 405 && code != 403 && code != 501 { return false }   // echte Fehler
        }
        // Manche Server lehnen HEAD ab → mit GET gegenprüfen (nur Kopf lesen).
        guard let (_, resp) = await holeBegrenzt(anfrage(url), maxBytes: 4096),
              let code = resp?.statusCode else { return false }
        return (200..<400).contains(code)
    }

    // MARK: Netz

    /// Nur echte Web-Adressen (kein file://, javascript:, data: …).
    private static func istWeb(_ url: URL) -> Bool {
        let s = url.scheme?.lowercased()
        return (s == "http" || s == "https") && url.host != nil
    }

    private static func anfrage(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 8)
        // Generischer User-Agent – niemals persönliche Daten.
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) Fundus", forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Lädt höchstens `maxBytes` Bytes als Stream und bricht dann ab (kein voller
    /// Body-Download vor der Größenprüfung → kein OOM durch riesige Antworten).
    private static func holeBegrenzt(_ req: URLRequest, maxBytes: Int) async -> (Data, HTTPURLResponse?)? {
        guard let (strom, resp) = try? await URLSession.shared.bytes(for: req) else { return nil }
        var daten = Data()
        daten.reserveCapacity(min(maxBytes, 65_536))
        do {
            for try await byte in strom {
                daten.append(byte)
                if daten.count >= maxBytes { break }
            }
        } catch { /* Teilantwort reicht */ }
        return (daten, resp as? HTTPURLResponse)
    }

    private static func hole(_ url: URL) async -> String? {
        guard istWeb(url), let (data, resp) = await holeBegrenzt(anfrage(url), maxBytes: 350_000),
              (resp.map { (200..<400).contains($0.statusCode) }) ?? true, !data.isEmpty
        else { return nil }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func holeDaten(_ url: URL?) async -> Data? {
        guard let url, istWeb(url),
              let (data, resp) = await holeBegrenzt(anfrage(url), maxBytes: 2_000_000),
              (resp.map { (200..<400).contains($0.statusCode) }) ?? true,
              !data.isEmpty
        else { return nil }
        return data
    }

    // MARK: Parsen

    private static func extrahiereTitel(_ html: String) -> String? {
        // <title> … </title> (auch mehrzeilig)
        guard let bereich = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>",
                                       options: [.regularExpression, .caseInsensitive]) else { return nil }
        var t = String(html[bereich])
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        t = entschluessle(t).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func faviconAdresse(_ html: String, basis: URL) -> URL? {
        // <link rel="... icon ..." href="...">
        let muster = "<link[^>]+rel=[\"'][^\"']*icon[^\"']*[\"'][^>]*>"
        guard let tagBereich = html.range(of: muster, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let tag = String(html[tagBereich])
        guard let hrefBereich = tag.range(of: "href=[\"']([^\"']+)[\"']",
                                          options: [.regularExpression, .caseInsensitive]) else { return nil }
        var href = String(tag[hrefBereich])
        href = href.replacingOccurrences(of: "href=", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        return URL(string: href, relativeTo: basis)?.absoluteURL
    }

    private static func entschluessle(_ s: String) -> String {
        var t = s
        let paare = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                     "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#x27;": "'"]
        for (k, v) in paare { t = t.replacingOccurrences(of: k, with: v) }
        return t
    }
}
