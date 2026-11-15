import Foundation
import AppKit

/// Rendert die erste Seite einer INDD-Datei über InDesign (ExtendScript) zu einer
/// echten Seitenvorschau. Opt-in, da InDesign dafür gestartet/benutzt wird.
enum InDesignRender {
    /// Welche InDesign-Version ist installiert? (bevorzugt die neuere)
    static var appName: String? {
        for v in ["2027", "2026", "2025", "2024"] {
            let pfad = "/Applications/Adobe InDesign \(v)/Adobe InDesign \(v).app"
            if FileManager.default.fileExists(atPath: pfad) { return "Adobe InDesign \(v)" }
        }
        return nil
    }
    static var verfuegbar: Bool { appName != nil }

    /// Exportiert Seite 1 als PNG nach `zielPNG`. Blockierend – im Hintergrund aufrufen.
    static func rendere(indd: URL, nach zielPNG: URL) -> Bool {
        guard let name = appName else { return false }
        let tmpDir = FileManager.default.temporaryDirectory
        let jpg = tmpDir.appendingPathComponent("fundus-indd-\(UUID().uuidString).jpg")
        let jsxURL = tmpDir.appendingPathComponent("fundus-indd-\(UUID().uuidString).jsx")
        defer {
            try? FileManager.default.removeItem(at: jpg)
            try? FileManager.default.removeItem(at: jsxURL)
        }

        // neverInteract unterdrückt modale Dialoge (fehlende Schriften/Verknüpfungen),
        // die sonst osascript dauerhaft blockieren; im finally sicher zurücksetzen.
        let jsx = """
        var _stufe = app.scriptPreferences.userInteractionLevel;
        app.scriptPreferences.userInteractionLevel = UserInteractionLevels.neverInteract;
        try {
          var doc = app.open(File(\(jsLiteral(indd.path))), false);
          app.jpegExportPreferences.jpegExportRange = ExportRangeOrAllPages.exportRange;
          app.jpegExportPreferences.pageString = doc.pages.item(0).name;
          app.jpegExportPreferences.exportResolution = 110;
          app.jpegExportPreferences.jpegQuality = JPEGOptionsQuality.high;
          doc.exportFile(ExportFormat.jpg, File(\(jsLiteral(jpg.path))), false);
          doc.close(SaveOptions.no);
        } finally {
          app.scriptPreferences.userInteractionLevel = _stufe;
        }
        """
        guard (try? jsx.write(to: jsxURL, atomically: true, encoding: .utf8)) != nil else { return false }

        let befehl = "tell application \"\(name)\" to do script (POSIX file \"\(jsxURL.path)\") language javascript"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", befehl]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        // Watchdog: hängt InDesign trotzdem (Start-/Anmeldedialog), nach 90 s abbrechen.
        guard Prozesslauf.fuehre(p, frist: 90) else { return false }

        guard FileManager.default.fileExists(atPath: jpg.path),
              let img = NSImage(contentsOf: jpg),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        try? FileManager.default.createDirectory(at: zielPNG.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        return (try? png.write(to: zielPNG)) != nil
    }

    /// Pfad als JavaScript-String-Literal (mit Anführungszeichen).
    private static func jsLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
