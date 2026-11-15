import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keine zusammengeführten Fenster-Tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        // System-Dienst „An Fundus senden" bereitstellen.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    /// Vor dem Beenden den aktuellen Stand sichern (Datenverlust vermeiden), dann
    /// das Beenden freigeben.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let app = AppModell.shared, app.bereit else { return .terminateNow }
        Task {
            await app.sichereBeimBeenden()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Dienst „An Fundus senden": nimmt Dateien, Links oder Text aus einer anderen
    /// App entgegen und legt sie auf der aktuellen Leinwand ab.
    @objc func anFundusSenden(_ pboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            AppModell.shared?.empfangeVonDienst(pboard)
        }
    }
}

@main
struct FundusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegat
    @StateObject private var app = AppModell()
    @StateObject private var kuerzel = Tastenkuerzel()

    var body: some Scene {
        // Einzelfenster (kein WindowGroup) → keine doppelten Fenster/Tabs.
        // Titelzeile trägt die lange Form; Dock/Menü zeigen „FUNDUS" (CFBundleDisplayName).
        Window("FUNDUS by dwbkd.de", id: "fundus") {
            Wurzel()
                .environmentObject(app)
                .environmentObject(kuerzel)
                .frame(minWidth: 900, minHeight: 600)
                .task { await app.starteFallsMoeglich() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Finden") {
                Button("Schnell finden …") { app.oeffnePalette() }
                    .kuerzel(kuerzel.kuerzel(.schnellsuche))
                Button("Gesundheits-Check …") { app.zeigeGesundheit = true }
                    .kuerzel(kuerzel.kuerzel(.gesundheit))
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Widerrufen") { app.rueckgaengig() }
                    .kuerzel(kuerzel.kuerzel(.widerrufen)).disabled(!app.kannUndo)
                Button("Wiederholen") { app.wiederherstellen() }
                    .kuerzel(kuerzel.kuerzel(.wiederholen)).disabled(!app.kannRedo)
            }
            CommandMenu("Objekt") {
                Button("Textfeld") { app.neueNotiz() }.kuerzel(kuerzel.kuerzel(.textfeld))
                Button("Notizzettel") { app.neuerZettel() }.kuerzel(kuerzel.kuerzel(.zettel))
                Button("Website-Link…") { app.starteLinkEingabe() }.kuerzel(kuerzel.kuerzel(.link))
                Button("Mappe") { app.neuerOrdner() }.kuerzel(kuerzel.kuerzel(.ordner))
                Button("Bereich") { app.neuerRahmen() }.kuerzel(kuerzel.kuerzel(.bereich))
                Divider()
                Button(app.verbindenModus ? "Verbinden beenden" : "Verbinden") { app.verbindungModusUmschalten() }
                    .kuerzel(kuerzel.kuerzel(.verbinden))
                Divider()
                Button("Neue Leinwand") { app.neueLeinwand() }.kuerzel(kuerzel.kuerzel(.neueLeinwand))
            }
            CommandMenu("Ansicht") {
                Button("Vergrößern") { app.zoomStufe(1.25) }.kuerzel(kuerzel.kuerzel(.vergroessern))
                Button("Verkleinern") { app.zoomStufe(0.8) }.kuerzel(kuerzel.kuerzel(.verkleinern))
                Button("Alles einpassen") { app.alleEinpassen() }.kuerzel(kuerzel.kuerzel(.einpassen))
                Button("Zoom zurücksetzen (100 %)") { app.zoomZuruecksetzen() }.kuerzel(kuerzel.kuerzel(.zoomReset))
                Divider()
                Button("Leinwand als Bild exportieren …") { app.exportiereLeinwand(alsPDF: false) }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Leinwand als PDF exportieren …") { app.exportiereLeinwand(alsPDF: true) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Paket exportieren …") { app.exportierePaket(nurAuswahl: false) }
                Button("Leinwand drucken …") { app.druckeLeinwand() }
                    .keyboardShortcut("p", modifiers: .command)
                Divider()
                Button("Tastaturbefehle…") { app.zeigeKuerzel = true }.kuerzel(kuerzel.kuerzel(.uebersicht))
            }
        }

        Settings {
            EinstellungenView().environmentObject(app)
        }
    }
}

/// Entscheidet: Datenbank schon geöffnet → Pinnwand, sonst Begrüßung/Ordnerwahl.
struct Wurzel: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        Group {
            if app.bereit {
                HauptAnsicht()
            } else {
                OnboardingView()
            }
        }
        .background(Design.papier)
        .onAppear { app.wendeErscheinungAn() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification)) { _ in app.beende() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in app.pruefeSicherung() }
    }
}

struct HauptAnsicht: View {
    @EnvironmentObject var app: AppModell
    @EnvironmentObject var kuerzel: Tastenkuerzel
    @State private var tastenWacht: Any?

    /// Basistaste aus einem Tastaturereignis (für die Kürzel-Aufnahme).
    private static func basisTaste(_ ev: NSEvent) -> String? {
        guard let ch = ev.charactersIgnoringModifiers?.lowercased(), let erste = ch.first else { return nil }
        if erste.isLetter || erste.isNumber { return String(erste) }
        if "+-/=.,;".contains(erste) { return String(erste) }
        return nil
    }

    private var loeschBinding: Binding<Bool> {
        Binding(get: { app.loeschKandidat != nil },
                set: { if !$0 { app.loeschKandidat = nil } })
    }
    private var mehrBinding: Binding<Bool> {
        Binding(get: { app.loeschMehrere }, set: { app.loeschMehrere = $0 })
    }

    /// Echter AppKit-Tasten-Monitor: Backspace (keyCode 51) löscht die Auswahl –
    /// aber nur, wenn gerade kein Textfeld bearbeitet wird.
    private func installiereTastenWacht() {
        guard tastenWacht == nil else { return }
        tastenWacht = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .scrollWheel]) { ev in
            if ev.type == .flagsChanged {            // ⌥ live verfolgen (Bereichsrahmen verschieben)
                let opt = ev.modifierFlags.contains(.option)
                MainActor.assumeIsolated { app.optionAktiv = opt }
                return ev
            }
            if ev.type == .scrollWheel {             // ⌘+Scroll → Zoom zum Mauszeiger
                guard ev.modifierFlags.contains(.command) else { return ev }
                let d = ev.scrollingDeltaY
                guard d != 0 else { return nil }
                let schritt = d * (ev.hasPreciseScrollingDeltas ? 0.004 : 0.03)
                MainActor.assumeIsolated { app.zoomAnPunkt(exp(schritt), punkt: app.mausPunkt) }
                return nil
            }
            // Leertaste loslassen: Schwenk-Modus beenden; war es nur ein Tippen (kein
            // Schwenken), QuickLook der gewählten Karte zeigen.
            if ev.type == .keyUp {
                if ev.keyCode == 49, !(NSApp.keyWindow?.firstResponder is NSText) {
                    MainActor.assumeIsolated {
                        let gezogen = app.spaceGezogen
                        app.spaceAktiv = false
                        app.spaceGezogen = false
                        if !gezogen, !QuickLookVorschau.shared.sichtbar,
                           case let .karte(id)? = app.auswahl,
                           let e = app.eintraege.first(where: { $0.id == id }), e.istDatei,
                           FileManager.default.fileExists(atPath: e.pfad) {
                            QuickLookVorschau.shared.zeige([e.url])
                        }
                    }
                    return nil
                }
                return ev
            }
            // Kürzel-Aufnahme: nächsten Tastendruck als neues Kürzel übernehmen.
            var aufnahmeLaeuft = false
            MainActor.assumeIsolated {
                guard let b = kuerzel.aufnahme else { return }
                aufnahmeLaeuft = true
                if ev.keyCode == 53 { kuerzel.aufnahme = nil; return }   // Esc = Abbruch
                if let t = HauptAnsicht.basisTaste(ev) {
                    let f = ev.modifierFlags
                    kuerzel.setze(b, Kuerzel(taste: t,
                        command: f.contains(.command), shift: f.contains(.shift),
                        option: f.contains(.option), control: f.contains(.control)))
                    kuerzel.aufnahme = nil
                }
                // unbrauchbare Taste → verschlucken, Aufnahme bleibt aktiv
            }
            if aufnahmeLaeuft { return nil }
            let imText = NSApp.keyWindow?.firstResponder is NSText
            if ev.modifierFlags.contains(.command), !imText,          // ⌘V → Zwischenablage ablegen
               ev.charactersIgnoringModifiers?.lowercased() == "v" {
                MainActor.assumeIsolated { app.fuegeAusZwischenablage() }
                return nil
            }
            if ev.keyCode == 49, !imText {           // Leertaste gedrückt halten → Schwenken
                if ev.isARepeat { return nil }
                // Offenes QuickLook-Panel schließt sich bei Leertaste selbst – dann
                // NICHT in den Schwenk-Modus wechseln (und beim Loslassen nicht neu öffnen).
                if QuickLookVorschau.shared.sichtbar {
                    MainActor.assumeIsolated { app.spaceAktiv = false; app.spaceGezogen = true }
                    return ev
                }
                MainActor.assumeIsolated { app.spaceAktiv = true; app.spaceGezogen = false }
                return nil
            }
            if ev.keyCode == 53 {                    // Esc → Verbinden-Modus beenden
                var verbraucht = false
                MainActor.assumeIsolated {
                    if app.verbindenModus { app.verbindungAbbrechen(); verbraucht = true }
                }
                if verbraucht { return nil }
            }
            if ev.keyCode == 51, !imText {           // Backspace/Delete
                var verbraucht = false
                MainActor.assumeIsolated {
                    if app.markierung.count > 1 { app.loeschMehrere = true; verbraucht = true }
                    else if app.auswahl != nil { app.loeschKandidat = app.auswahl; verbraucht = true }
                }
                return verbraucht ? nil : ev
            }
            return ev
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            LeinwandView()
                .ignoresSafeArea()
            HStack {
                BereichsNavigation()
                Spacer()
            }
            .padding(.leading, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Kopfleiste()
            InspektorLeiste()
                .padding(.top, 116)
                .animation(.easeOut(duration: 0.15), value: app.auswahl)
            if let m = app.exportMeldung {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up.circle.fill").foregroundStyle(Design.neonCyan)
                        Text(m).font(Design.grotesk(12.5, gewicht: .medium)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Design.paneel, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .padding(.bottom, 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: m) {
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    app.exportMeldung = nil
                }
            }
            if app.zeigePalette {
                Schnellsuche()
                    .environmentObject(app)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
        }
        .overlay(alignment: .bottomTrailing) { MiniKarte().padding(16) }
        .animation(.easeOut(duration: 0.15), value: app.zeigePalette)
        .animation(.easeOut(duration: 0.2), value: app.exportMeldung)
        .onAppear { installiereTastenWacht() }
        .onDisappear { if let m = tastenWacht { NSEvent.removeMonitor(m); tastenWacht = nil } }
        .alert("Entfernen?", isPresented: loeschBinding, presenting: app.loeschKandidat) { _ in
            Button("Entfernen", role: .destructive) { app.entferneKandidaten() }
            Button("Abbrechen", role: .cancel) { app.loeschKandidat = nil }
        } message: { kandidat in
            switch kandidat {
            case .ordner:
                Text("Die Mappe „\(app.kandidatName)“ wird aufgelöst – die Karten bleiben erhalten.")
            case .karte:
                Text("„\(app.kandidatName)“ wird von der Pinnwand entfernt. Die Originaldatei bleibt erhalten.")
            case .notiz:
                Text("Das Textfeld wird gelöscht.")
            }
        }
        .alert("Objekte entfernen?", isPresented: mehrBinding) {
            Button("Entfernen", role: .destructive) { app.entferneMarkierung() }
            Button("Abbrechen", role: .cancel) { app.loeschMehrere = false }
        } message: {
            Text("\(app.markierung.count) Objekte werden entfernt. Originaldateien bleiben erhalten.")
        }
        .sheet(isPresented: $app.linkSheet) {
            LinkEingabe().environmentObject(app)
        }
        .sheet(isPresented: $app.zeigeKuerzel) {
            KuerzelUebersicht().environmentObject(app).environmentObject(kuerzel)
        }
        .sheet(isPresented: $app.zeigeReparatur) {
            ReparaturPanel().environmentObject(app)
        }
        .sheet(isPresented: $app.zeigeGesundheit) {
            GesundheitsPanel().environmentObject(app)
        }
    }
}

/// Schwebende Bedienung über der Leinwand: links Leinwand-Reiter + Werkzeuge,
/// rechts Suche + Ansicht. Alle Gruppen sind freischwebende Glas-Paneele; die
/// Zwischenräume lassen die Leinwand durch.
struct Kopfleiste: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 9) {
                reiterPanel
                werkzeugPanel
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 9) {
                suchPanel
                ansichtPanel
            }
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    /// Einheitliches, dunkles schwebendes Paneel (helle Schrift/Icons).
    private func glas<Inhalt: View>(@ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        inhalt()
            .environment(\.colorScheme, .dark)
            .background(Design.paneel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 7)
    }

    // Links oben: Leinwand-Reiter
    private var reiterPanel: some View {
        glas {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(app.boards) { b in ReiterAnsicht(b: b) }
                    Button { app.neueLeinwand() } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain).foregroundStyle(Design.paneelInhalt)
                    .help("Neue Leinwand")
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
            }
            .frame(maxWidth: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Links oben: die schwebende Werkzeug-Leiste (senkrecht)
    private var werkzeugPanel: some View {
        glas {
            VStack(spacing: 4) {
                WerkzeugIkon(symbol: "character.textbox", titel: "Textfeld", kuerzel: "⌘T") { app.neueNotiz() }
                WerkzeugIkon(symbol: "note.text", titel: "Notizzettel", kuerzel: "⌘⇧T") { app.neuerZettel() }
                WerkzeugIkon(symbol: "globe", titel: "Website-Link", kuerzel: "⌘L") { app.starteLinkEingabe() }
                WerkzeugIkon(symbol: "folder.badge.plus", titel: "Mappe", kuerzel: "⌘⇧O") { app.neuerOrdner() }
                WerkzeugIkon(symbol: "rectangle.dashed", titel: "Bereich", kuerzel: "⌘⇧B") { app.neuerRahmen() }
                trenner
                WerkzeugIkon(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                             titel: app.verbindenModus
                                ? (app.verbindeVon == nil ? "1. Element wählen" : "2. Element wählen") : "Verbinden",
                             kuerzel: "⌘U",
                             hervor: app.verbindenModus) { app.verbindungModusUmschalten() }
                trenner
                WerkzeugIkon(symbol: "arrow.uturn.backward", titel: "Widerrufen", kuerzel: "⌘Z",
                             aktiv: app.kannUndo) { app.rueckgaengig() }
                WerkzeugIkon(symbol: "arrow.uturn.forward", titel: "Wiederholen", kuerzel: "⇧⌘Z",
                             aktiv: app.kannRedo) { app.wiederherstellen() }
            }
            .padding(.horizontal, 5).padding(.vertical, 7)
        }
        .fixedSize()
    }

    // Rechts oben: Suche + aufklappende Ergebnisliste
    private var suchPanel: some View {
        glas {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13))
                        .foregroundStyle(Design.paneelInhalt)
                    TextField("Durchsuchen – Name & Inhalt (PDF, OCR, IDML, Ordner …)", text: $app.suchtext)
                        .textFieldStyle(.plain).font(Design.grotesk(13.5))
                        .foregroundStyle(Design.paneelInhalt).frame(minWidth: 240)
                    if !app.suchtext.isEmpty {
                        Button { app.suchtext = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Design.paneelInhalt)
                        }.buttonStyle(.plain)
                    }
                    Rectangle().fill(Design.rahmen).frame(width: 1, height: 16)
                    if app.trefferIDs != nil {
                        Text("\(app.sucheTreffer.count) Treffer")
                            .font(Design.grotesk(12, gewicht: .semibold)).foregroundStyle(Design.neonCyan)
                    } else {
                        Text("\(app.eintraege.count) Dok.")
                            .font(Design.grotesk(12, gewicht: .medium)).foregroundStyle(Design.paneelInhalt)
                    }
                    if !app.defekteEintraege.isEmpty {
                        Button { app.reparaturMeldung = nil; app.zeigeReparatur = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("\(app.defekteEintraege.count)")
                            }
                            .font(Design.grotesk(11, gewicht: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Design.neonFuchsia, in: Capsule())
                        }
                        .buttonStyle(.plain).help("Defekte Verknüpfungen reparieren")
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 9)

                if app.trefferIDs != nil {
                    Divider().opacity(0.5)
                    ergebnisListe
                }
            }
            .frame(maxWidth: 460)
        }
    }

    @ViewBuilder private var ergebnisListe: some View {
        let treffer = app.sucheTreffer
        if treffer.isEmpty {
            Text("Keine Treffer").font(Design.grotesk(12)).foregroundStyle(Design.gedaempft)
                .padding(.horizontal, 14).padding(.vertical, 12)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(treffer) { e in ErgebnisZeile(e: e) }
                }
            }
            .frame(maxHeight: min(CGFloat(treffer.count) * 44 + 4, 300))
        }
    }

    // Rechts oben: Zoom + Datenbank-Ort
    private var ansichtPanel: some View {
        glas {
            HStack(spacing: 2) {
                Button { setzeZoom(app.zoom / 1.25) } label: {
                    Image(systemName: "minus").frame(width: 24, height: 24)
                }
                Text("\(Int(app.zoom * 100)) %")
                    .font(Design.grotesk(11, gewicht: .medium)).foregroundStyle(Design.paneelInhalt)
                    .frame(width: 44)
                Button { setzeZoom(app.zoom * 1.25) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                Button { setzeZoom(1); app.schwenk = .zero; app.sichereKamera() } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 24, height: 24)
                }.help("Ansicht zurücksetzen")
                Rectangle().fill(Design.rahmen).frame(width: 1, height: 16)
                Menu {
                    Button("Als Bild (PNG)") { app.exportiereLeinwand(alsPDF: false) }
                    Button("Als PDF") { app.exportiereLeinwand(alsPDF: true) }
                    Divider()
                    Button("Paket exportieren (alle Dateien + Manifest) …") { app.exportierePaket(nurAuswahl: false) }
                    Button("Auswahl als Paket exportieren …") { app.exportierePaket(nurAuswahl: true) }
                        .disabled(app.auswahl == nil && app.markierung.isEmpty)
                    Divider()
                    Button("Drucken …") { app.druckeLeinwand() }
                } label: {
                    Image(systemName: "square.and.arrow.up").frame(width: 26, height: 24)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Leinwand exportieren / teilen")
                Button { app.wechsleErscheinung() } label: {
                    Image(systemName: app.istDunkel ? "sun.max" : "moon").frame(width: 26, height: 24)
                }.help(app.istDunkel ? "Heller Modus" : "Dunkler Modus")
                Button { app.gesundheit = nil; app.zeigeGesundheit = true } label: {
                    Image(systemName: "stethoscope").frame(width: 26, height: 24)
                }.help("Gesundheits-Check (fehlende Dateien, tote Links, Dubletten)")
                Button { app.zeigeKuerzel = true } label: {
                    Image(systemName: "keyboard").frame(width: 28, height: 24)
                }.help("Tastaturbefehle anzeigen")
                Button { if let u = Dateiauswahl.ordner() { Task { await app.waehleOrt(u) } } } label: {
                    Image(systemName: "externaldrive.connected.to.line.below").frame(width: 28, height: 24)
                }.help("Datenbank-Ordner wechseln")
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain).foregroundStyle(Design.paneelInhalt)
            .padding(.horizontal, 8).padding(.vertical, 5)
        }
    }

    private var trenner: some View {
        Rectangle().fill(Design.rahmen).frame(width: 22, height: 1).padding(.vertical, 1)
    }

    private func setzeZoom(_ z: Double) {
        app.zoom = min(max(z, 0.25), 4)
        app.sichereKamera()
    }
}

/// Reiner Symbol-Knopf für die schwebende Werkzeugleiste. Der Name erscheint
/// erst als Tooltip, wenn man länger darauf verweilt (`.help`).
struct WerkzeugIkon: View {
    let symbol: String
    let titel: String
    var kuerzel: String = ""           // für den Tooltip, z. B. „⌘T"
    var aktiv: Bool = true
    var hervor: Bool = false
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hervor ? AnyShapeStyle(.white) : AnyShapeStyle(Design.paneelInhalt))
                .frame(width: 34, height: 30)
                .background(hervor ? AnyShapeStyle(Design.neon)
                                   : AnyShapeStyle(Color.white.opacity(hover ? 0.18 : 0.0)),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(aktiv ? 1 : 0.4).disabled(!aktiv)
        .onHover { hover = $0 }
        .help(kuerzel.isEmpty ? titel : "\(titel)  (\(kuerzel))")
    }
}

/// Eine Zeile in der Suchergebnis-Liste. Klick schiebt das Objekt in die Mitte.
struct ErgebnisZeile: View {
    @EnvironmentObject var app: AppModell
    let e: Eintrag
    @State private var hover = false

    private var symbol: String {
        if e.istWeblink { return "globe" }
        if e.istOrdnerRef { return "folder.fill" }
        return e.kategorie.symbol
    }
    private var unter: String {
        if e.istWeblink { return e.webHost }
        if e.istOrdnerRef { return "Finder-Ordner" }
        return e.groesseText.isEmpty ? e.endung.uppercased() : e.groesseText
    }

    var body: some View {
        Button { app.zentriere(e.id) } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Design.neon).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.name).font(Design.grotesk(12.5, gewicht: .medium)).foregroundStyle(Design.tinte)
                        .lineLimit(1).truncationMode(.middle)
                    Text(unter).font(Design.grotesk(10)).foregroundStyle(Design.gedaempft).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "scope").font(.system(size: 11))
                    .foregroundStyle(Design.neonCyan).opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("In die Mitte rücken")
    }
}

/// Übersicht aller Tastaturbefehle – jedes Kürzel ist per Klick neu belegbar.
struct KuerzelUebersicht: View {
    @EnvironmentObject var app: AppModell
    @EnvironmentObject var kuerzel: Tastenkuerzel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "keyboard").font(.system(size: 18)).foregroundStyle(Design.neonCyan)
                Text("Tastaturbefehle").font(Design.serife(17, gewicht: .semibold))
                Spacer()
                Text("Klick auf ein Kürzel → neue Taste drücken")
                    .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Werkzeugbefehl.gruppen, id: \.self) { gruppe in
                        let befehle = Werkzeugbefehl.allCases.filter { $0.gruppe == gruppe }
                        if !befehle.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gruppe.uppercased())
                                    .font(Design.grotesk(10, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
                                    .padding(.leading, 4)
                                ForEach(befehle) { b in zeile(b) }
                            }
                        }
                    }
                    // Maus- und Trackpad-Gesten (nicht einzeln belegbar).
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MAUS & TRACKPAD")
                            .font(Design.grotesk(10, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
                            .padding(.leading, 4)
                        gesteZeile("hand.draw", "Leinwand schwenken", "Leertaste halten + ziehen")
                        gesteZeile("rectangle.dashed", "Bereich verschieben", "⌥ (Option) halten + ziehen")
                        gesteZeile("plus.magnifyingglass", "Zoomen", "⌘ + Scrollrad")
                        gesteZeile("lasso", "Mehrfachauswahl", "⇧ + klicken · leere Fläche ziehen")
                        gesteZeile("eye", "Schnellvorschau (QuickLook)", "Leertaste antippen (Karte gewählt)")
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button("Alle auf Standard zurücksetzen") { kuerzel.allesZuruecksetzen(); kuerzel.aufnahme = nil }
                Spacer()
                Button("Fertig") { kuerzel.aufnahme = nil; app.zeigeKuerzel = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 460, height: 560)
        .onDisappear { kuerzel.aufnahme = nil }
    }

    /// Informationszeile für eine Maus-/Trackpad-Geste (nicht belegbar).
    private func gesteZeile(_ symbol: String, _ titel: String, _ geste: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Design.neon).frame(width: 22)
            Text(titel).font(Design.grotesk(13)).foregroundStyle(Design.tinte)
            Spacer(minLength: 8)
            Text(geste)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Design.gedaempft)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.gray.opacity(0.12)))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func zeile(_ b: Werkzeugbefehl) -> some View {
        let aktiv = kuerzel.aufnahme == b
        let k = kuerzel.kuerzel(b)
        return HStack(spacing: 10) {
            Image(systemName: b.symbol).font(.system(size: 12)).foregroundStyle(Design.neon)
                .frame(width: 22)
            Text(b.titel).font(Design.grotesk(13)).foregroundStyle(Design.tinte)
            Spacer(minLength: 8)
            if kuerzel.istEigen(b) {
                Button { kuerzel.zuruecksetzen(b) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10))
                }.buttonStyle(.plain).foregroundStyle(Design.gedaempft).help("Auf Standard zurücksetzen")
            }
            Button { kuerzel.aufnahme = aktiv ? nil : b } label: {
                Text(aktiv ? "Taste drücken … (Esc bricht ab)" : k.anzeige)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(aktiv ? .white : (k.belegt ? Design.tinte : Design.gedaempft))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((aktiv ? AnyShapeStyle(Design.neon) : AnyShapeStyle(Color.gray.opacity(0.15))),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(aktiv ? Color.clear : Design.rahmen))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(aktiv ? Design.neonCyan.opacity(0.08) : Color.clear))
    }
}

/// Panel für defekte Verknüpfungen: Sammel-Relink per Ordnersuche oder einzeln.
struct ReparaturPanel: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "bandage").font(.system(size: 18)).foregroundStyle(Design.neonFuchsia)
                Text("Verknüpfungen reparieren").font(Design.serife(17, gewicht: .semibold))
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)

            HStack(spacing: 10) {
                Text(app.defekteEintraege.isEmpty
                     ? "Alle Verknüpfungen sind in Ordnung."
                     : "\(app.defekteEintraege.count) Karte(n) zeigen auf fehlende Dateien.")
                    .font(Design.grotesk(12)).foregroundStyle(Design.gedaempft)
                Spacer()
                if let m = app.reparaturMeldung {
                    Text(m).font(Design.grotesk(12, gewicht: .semibold)).foregroundStyle(Design.neonCyan)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10)

            if !app.defekteEintraege.isEmpty {
                Button {
                    app.waehleReparaturOrdner()
                } label: {
                    Label("Ordner wählen und automatisch neu verknüpfen …", systemImage: "folder.badge.gearshape")
                        .font(Design.grotesk(12, gewicht: .semibold))
                }
                .padding(.horizontal, 20).padding(.bottom, 8)

                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(app.defekteEintraege) { e in
                            HStack(spacing: 9) {
                                Image(systemName: "doc.badge.ellipsis").foregroundStyle(Design.neonFuchsia)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(e.name).font(Design.grotesk(12.5, gewicht: .medium))
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(e.pfad).font(Design.grotesk(9.5)).foregroundStyle(Design.gedaempft)
                                        .lineLimit(1).truncationMode(.head)
                                }
                                Spacer(minLength: 8)
                                Button("Datei wählen …") {
                                    if let url = Dateiauswahl.datei() { app.neuVerknuepfe(e, mit: url) }
                                }.font(Design.grotesk(11))
                            }
                            .padding(.horizontal, 20).padding(.vertical, 7)
                            Divider().opacity(0.3)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Spacer()
                Button("Fertig") { app.zeigeReparatur = false }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 480)
    }
}

/// Eingabe-Sheet für einen Website-Link (neu oder bearbeiten).
struct LinkEingabe: View {
    @EnvironmentObject var app: AppModell
    @FocusState private var fokusAdresse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(Design.neonCyan)
                Text(app.linkBearbeiteID == nil ? "Website-Link hinterlegen" : "Link bearbeiten")
                    .font(Design.serife(17, gewicht: .semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Adresse").font(Design.grotesk(11, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
                TextField("example.com", text: $app.linkEntwurfAdresse)
                    .textFieldStyle(.roundedBorder).focused($fokusAdresse)
                    .onSubmit { app.bestaetigeLinkEingabe() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Titel (optional)").font(Design.grotesk(11, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
                TextField("Wird sonst aus der Adresse übernommen", text: $app.linkEntwurfTitel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { app.bestaetigeLinkEingabe() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Notiz (optional)").font(Design.grotesk(11, gewicht: .semibold)).foregroundStyle(Design.gedaempft)
                TextEditor(text: $app.linkEntwurfKommentar)
                    .font(Design.grotesk(12.5))
                    .frame(height: 70)
                    .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Design.rahmen))
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.12)))
            }
            HStack {
                Spacer()
                Button("Abbrechen") { app.linkSheet = false }.keyboardShortcut(.cancelAction)
                Button(app.linkBearbeiteID == nil ? "Hinzufügen" : "Sichern") { app.bestaetigeLinkEingabe() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(app.linkEntwurfAdresse.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { DispatchQueue.main.async { fokusAdresse = true } }
    }
}

/// Ein Leinwand-Reiter.
struct ReiterAnsicht: View {
    @EnvironmentObject var app: AppModell
    let b: BoardInfo
    @State private var bearbeite = false
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    private var aktiv: Bool { app.aktivBoard == b.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11, weight: .semibold))
            if bearbeite {
                TextField("Name", text: $entwurf)
                    .textFieldStyle(.plain).font(Design.grotesk(13.5, gewicht: .semibold))
                    .focused($fokus).frame(width: 120)
                    .onSubmit(commit)
            } else {
                Text(b.name).font(Design.grotesk(13.5, gewicht: aktiv ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .foregroundStyle(aktiv ? AnyShapeStyle(.white) : AnyShapeStyle(Design.paneelInhalt))
        .background {
            if aktiv { Capsule().fill(Design.neon) }
            else { Capsule().fill(Color.white.opacity(0.06)) }
        }
        .contentShape(Capsule())
        .onTapGesture { if !bearbeite { app.wechsleBoard(b.id) } }
        .onTapGesture(count: 2) { starte() }
        .contextMenu {
            Button("Umbenennen") { starte() }
            Button("Duplizieren") { app.dupliziereLeinwand(b.id) }
            if app.boards.count > 1 {
                Divider()
                Button("Leinwand löschen", role: .destructive) { app.loescheLeinwand(b.id) }
            }
        }
    }

    private func starte() {
        entwurf = b.name
        bearbeite = true
        DispatchQueue.main.async { fokus = true }
    }
    private func commit() {
        app.benenneLeinwand(b.id, entwurf)
        bearbeite = false
    }
}

/// Gefüllter Pill-Knopf für die Werkzeugleiste.
struct WerkzeugKnopf: View {
    let titel: String
    let symbol: String
    let aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(Design.neon)
                Text(titel).foregroundStyle(Design.tinte)
            }
            .font(Design.grotesk(11, gewicht: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Color.white.opacity(hover ? 0.15 : 0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Design.rahmen))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Vertikale Navigation über die übergeordneten Bereiche (wie „Seiten", nur
/// senkrecht). Klick fährt die Kamera auf den Bereich.
struct BereichsNavigation: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        if !app.rahmenListe.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Design.neon)
                    Text("Bereiche").font(Design.grotesk(12, gewicht: .semibold)).foregroundStyle(Design.paneelInhalt)
                    Spacer(minLength: 8)
                    Button { app.neuerRahmen() } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Design.paneelInhalt)
                    }.buttonStyle(.plain).help("Neuen Bereich anlegen")
                }
                .padding(.bottom, 2)

                ForEach(app.rahmenListe) { r in BereichsZeile(r: r) }
            }
            .environment(\.colorScheme, .dark)
            .padding(10)
            .frame(width: 194)
            .background(Design.paneel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 7)
        }
    }
}

struct BereichsZeile: View {
    @EnvironmentObject var app: AppModell
    let r: Rahmen
    @State private var hover = false
    private var aktiv: Bool { app.aktiverRahmen == r.id }
    private var farbe: Color { Design.objektFarbe(r.farbe) }

    var body: some View {
        Button { app.springeZuRahmen(r.id) } label: {
            HStack(spacing: 8) {
                Circle().fill(farbe).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
                Text(r.name).font(Design.grotesk(12.5, gewicht: aktiv ? .semibold : .regular))
                    .foregroundStyle(aktiv ? AnyShapeStyle(.white) : AnyShapeStyle(Design.paneelInhalt))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((aktiv ? farbe.opacity(0.22) : (hover ? Color.white.opacity(0.08) : Color.clear)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Hierher springen") { app.springeZuRahmen(r.id) }
            Divider()
            Button("Bereich löschen", role: .destructive) { app.loescheRahmen(r.id) }
        }
    }
}

/// Zentrale Helfer für die Ordner-/Datei-Auswahl (NSOpenPanel).
enum Dateiauswahl {
    static func ordner() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Hier ablegen"
        panel.message = "Ordner für die Fundus-Datenbank wählen – z. B. in der Nextcloud, "
            + "damit sie eine Neuinstallation übersteht."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func datei() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Verknüpfen"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Neues Ziel für eine defekte Karte wählen – Datei oder Ordner.
    static func neuesZiel(ordner: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = ordner
        panel.canChooseFiles = !ordner
        panel.allowsMultipleSelection = false
        panel.prompt = "Verknüpfen"
        panel.message = ordner ? "Verschobenen Ordner wählen." : "Verschobene Datei wählen."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func sicherungsOrdner() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Hierhin sichern"
        panel.message = "Ordner für die Backups wählen – gern auf einem externen oder "
            + "gemounteten Netzlaufwerk. Fundus legt dort einen Ordner „Fundus-Sicherung“ an."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func paketOrdner() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Hierhin exportieren"
        panel.message = "Zielordner für das Fundus-Paket wählen – die referenzierten Dateien "
            + "werden hierhin kopiert, zusammen mit einem Manifest."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reparaturOrdner() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Hier suchen"
        panel.message = "Ordner wählen – Fundus sucht darin (auch in Unterordnern) nach "
            + "gleichnamigen Dateien für die defekten Karten."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
