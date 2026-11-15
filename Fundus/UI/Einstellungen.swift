import SwiftUI

/// Erste Begrüßung, solange noch kein Datenbank-Ordner gewählt ist.
struct OnboardingView: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        ZStack {
            Design.leinwandVerlauf.ignoresSafeArea()
            RasterHintergrund(zoom: 1, schwenk: .zero).ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Design.neon)
                    .shadow(color: Design.neonViolett.opacity(0.6), radius: 22)
                Text("Fundus")
                    .font(Design.serife(36, gewicht: .bold))
                    .foregroundStyle(.white)
                Text("Zieh Dokumente auf die Pinnwand – sie bleiben an ihrem Ort, Fundus merkt "
                     + "sich nur den Pfad und macht den Inhalt durchsuchbar.")
                    .font(Design.grotesk(14)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)

                Button {
                    if let u = Dateiauswahl.ordner() { Task { await app.waehleOrt(u) } }
                } label: {
                    Label("Datenbank-Ordner wählen …", systemImage: "folder.badge.plus")
                        .font(Design.grotesk(13, gewicht: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Design.neon, in: Capsule())
                .shadow(color: Design.neonViolett.opacity(0.5), radius: 14, y: 4)

                Text("Tipp: einen Ordner in der Nextcloud wählen – dann übersteht die Sammlung "
                     + "eine Neuinstallation.")
                    .font(Design.grotesk(11)).foregroundStyle(.white.opacity(0.5))

                if let f = app.fehler {
                    Text(f).font(Design.grotesk(11)).foregroundStyle(Design.neonFuchsia)
                        .multilineTextAlignment(.center).frame(maxWidth: 440)
                }
            }
            .padding(40)
        }
    }
}

/// Einstellungen (⌘,): Datenbank-Ort und OCR.
struct EinstellungenView: View {
    @EnvironmentObject var app: AppModell

    var body: some View {
        Form {
            Section("Datenbank") {
                LabeledContent("Ordner") {
                    Text(app.dbOrt?.path ?? "– noch nicht gewählt –")
                        .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
                        .lineLimit(1).truncationMode(.middle)
                }
                Button("Ordner wechseln …") {
                    if let u = Dateiauswahl.ordner() { Task { await app.waehleOrt(u) } }
                }
            }
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: Binding(
                    get: { app.erscheinung }, set: { app.erscheinung = $0 })) {
                    ForEach(AppModell.Erscheinung.allCases) { e in Text(e.titel).tag(e) }
                }
                .pickerStyle(.segmented)
                Text("Hell schaltet die Leinwand auf helles Papier um; die schwebenden "
                     + "Bedien-Paneele bleiben dunkel. „System“ folgt dem Mac.")
                    .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
            }
            Section("Indizierung") {
                Toggle("Gescannte PDFs und Bilder per Texterkennung (OCR) durchsuchbar machen",
                       isOn: $app.ocrAktiv)
                    .onChange(of: app.ocrAktiv) { _, neu in
                        UserDefaults.standard.set(neu, forKey: "ocrAktiv")
                    }
                Text("Ohne OCR wird nur echter, eingebetteter Text erfasst – der Import ist dann schneller.")
                    .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
            }
            Section("Sicherung") {
                Toggle("Automatische Sicherung auf ein externes/Netz-Laufwerk",
                       isOn: Binding(get: { app.backupAktiv }, set: { app.setzeBackupAktiv($0) }))
                LabeledContent("Ziel") {
                    Text(app.backupOrt?.path ?? "– noch nicht gewählt –")
                        .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Backup-Ordner wählen …") { app.waehleBackupOrt() }
                    Spacer()
                    Button("Jetzt sichern") { app.sichereJetzt(gross: false) }
                        .disabled(app.backupOrt == nil)
                    Button("Großes Backup jetzt") { app.sichereJetzt(gross: true) }
                        .disabled(app.backupOrt == nil)
                }
                Text("Regulär alle 2 Tage (nur die Datenbank), zusätzlich einmal pro Woche ein "
                     + "großes Backup mit Vorschauen – jeweils als eigene, datierte Kopie. "
                     + "Geprüft wird beim Start und beim Aktivieren.")
                    .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
                if let s = app.backupStatus {
                    Text(s).font(Design.grotesk(11, gewicht: .medium)).foregroundStyle(Design.akzent)
                }
                if let r = app.backupLetzteRegulaer {
                    Text("Letztes reguläres Backup: \(r.formatted(date: .abbreviated, time: .shortened))")
                        .font(Design.grotesk(10)).foregroundStyle(Design.gedaempft)
                }
                if let w = app.backupLetzteWoche {
                    Text("Letztes Wochen-Backup: \(w.formatted(date: .abbreviated, time: .shortened))")
                        .font(Design.grotesk(10)).foregroundStyle(Design.gedaempft)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
    }
}
