import SwiftUI

/// Gesundheits-Check einer Leinwand: fehlende Dateien, nicht erreichbare
/// Web-Links und Dubletten (mehrfach referenzierte Dateien). Prüft beim Öffnen.
struct GesundheitsPanel: View {
    @EnvironmentObject var app: AppModell

    private var bericht: GesundheitsBericht? { app.gesundheit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            kopf
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let b = bericht {
                        if b.allesInOrdnung && b.ohneLesezeichen == 0 {
                            hinweis("checkmark.seal.fill", Design.neonCyan,
                                    "Alles in Ordnung – keine fehlenden Dateien, toten Links oder Dubletten.")
                        }
                        if b.ohneLesezeichen > 0 {
                            absichern(b.ohneLesezeichen)
                        }
                        if !b.fehlende.isEmpty { fehlendeAbschnitt(b.fehlende) }
                        linkAbschnitt(b)
                        if !b.dubletten.isEmpty { dublettenAbschnitt(b.dubletten) }
                    } else {
                        hinweis("stethoscope", Design.gedaempft, "Prüfung läuft …")
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button { app.starteGesundheitsCheck() } label: {
                    Label("Erneut prüfen", systemImage: "arrow.clockwise")
                }
                if app.gesundheitLaeuft { ProgressView().controlSize(.small).padding(.leading, 6) }
                Spacer()
                Button("Fertig") { app.zeigeGesundheit = false }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 560, height: 580)
        .onAppear { if app.gesundheit == nil { app.starteGesundheitsCheck() } }
    }

    private var kopf: some View {
        HStack(spacing: 9) {
            Image(systemName: "stethoscope").font(.system(size: 18)).foregroundStyle(Design.neonCyan)
            Text("Gesundheits-Check").font(Design.serife(17, gewicht: .semibold))
            Spacer()
            if let b = bericht {
                Text("\(b.fehlende.count) fehlend · \(b.linksGeprueft ? "\(b.toteLinks.count)" : "…") tote Links · \(b.dubletten.count) Dubletten")
                    .font(Design.grotesk(11)).foregroundStyle(Design.gedaempft)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
    }

    private func hinweis(_ symbol: String, _ farbe: Color, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(farbe)
            Text(text).font(Design.grotesk(12.5)).foregroundStyle(Design.tinte)
        }
    }

    // MARK: Lesezeichen absichern

    private func absichern(_ anzahl: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            abschnittTitel("square.and.arrow.down.on.square", "Referenzen absichern")
            HStack(spacing: 10) {
                Text("\(anzahl) Karte(n) haben noch kein Lesezeichen. Damit übersteht die "
                     + "Verknüpfung ein Verschieben oder Umbenennen der Datei.")
                    .font(Design.grotesk(11.5)).foregroundStyle(Design.gedaempft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Jetzt absichern") { app.sichereAlleLesezeichen() }
                    .font(Design.grotesk(11, gewicht: .semibold))
            }
        }
    }

    // MARK: Fehlende Dateien

    private func fehlendeAbschnitt(_ liste: [Eintrag]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            abschnittTitel("exclamationmark.triangle.fill", "Fehlende Dateien (\(liste.count))", Design.neonFuchsia)
            ForEach(liste) { e in
                zeile(symbol: e.istOrdnerRef ? "folder.badge.questionmark" : "doc.badge.ellipsis",
                      farbe: Design.neonFuchsia, titel: e.name, unter: e.pfad) {
                    Button("Neu wählen …") {
                        if let url = Dateiauswahl.neuesZiel(ordner: e.istOrdnerRef) { app.neuVerknuepfe(e, mit: url) }
                    }.font(Design.grotesk(11))
                    springKnopf(e.id)
                }
            }
        }
    }

    // MARK: Tote Links

    private func linkAbschnitt(_ b: GesundheitsBericht) -> some View {
        Group {
            if !b.linksGeprueft {
                hinweis("globe", Design.gedaempft, "Web-Links werden geprüft …")
            } else if !b.toteLinks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    abschnittTitel("globe.badge.chevron.backward", "Nicht erreichbare Links (\(b.toteLinks.count))", Design.neonFuchsia)
                    ForEach(b.toteLinks) { e in
                        zeile(symbol: "globe", farbe: Design.neonFuchsia, titel: e.name, unter: e.pfad) {
                            Button("Öffnen") { app.oeffne(e) }.font(Design.grotesk(11))
                            Button("Bearbeiten …") { app.springeZuKarte(e.id); app.starteLinkBearbeiten(e.id) }
                                .font(Design.grotesk(11))
                            springKnopf(e.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: Dubletten

    private func dublettenAbschnitt(_ gruppen: [[Eintrag]]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            abschnittTitel("doc.on.doc", "Dubletten (\(gruppen.count))", Design.objektFarbe(3))
            ForEach(Array(gruppen.enumerated()), id: \.offset) { _, gruppe in
                VStack(alignment: .leading, spacing: 2) {
                    Text(gruppe.first?.name ?? "")
                        .font(Design.grotesk(12.5, gewicht: .semibold)).foregroundStyle(Design.tinte)
                        .lineLimit(1).truncationMode(.middle)
                    Text("\(gruppe.count)× dieselbe Datei referenziert")
                        .font(Design.grotesk(10)).foregroundStyle(Design.gedaempft)
                    ForEach(Array(gruppe.enumerated()), id: \.element.id) { i, e in
                        HStack(spacing: 8) {
                            Image(systemName: i == 0 ? "1.circle" : "doc.on.doc.fill")
                                .font(.system(size: 11)).foregroundStyle(i == 0 ? Design.akzent : Design.gedaempft)
                                .frame(width: 18)
                            Text(e.pfad).font(Design.grotesk(9.5)).foregroundStyle(Design.gedaempft)
                                .lineLimit(1).truncationMode(.head)
                            Spacer(minLength: 8)
                            springKnopf(e.id)
                            if i > 0 {
                                Button("Entfernen") { app.entferne(e) }
                                    .font(Design.grotesk(10.5)).foregroundStyle(Design.neonFuchsia)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
            }
        }
    }

    // MARK: Bausteine

    private func abschnittTitel(_ symbol: String, _ titel: String, _ farbe: Color = Design.akzent) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(farbe)
            Text(titel).font(Design.grotesk(11.5, gewicht: .semibold)).foregroundStyle(Design.tinte)
        }
    }

    private func zeile<Aktionen: View>(symbol: String, farbe: Color, titel: String, unter: String,
                                       @ViewBuilder _ aktionen: () -> Aktionen) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(farbe).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(titel).font(Design.grotesk(12.5, gewicht: .medium)).foregroundStyle(Design.tinte)
                    .lineLimit(1).truncationMode(.middle)
                Text(unter).font(Design.grotesk(9.5)).foregroundStyle(Design.gedaempft)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            aktionen()
        }
        .padding(.vertical, 3)
    }

    private func springKnopf(_ id: Int) -> some View {
        Button { app.springeZuKarte(id) } label: {
            Image(systemName: "scope").font(.system(size: 12)).foregroundStyle(Design.neonCyan)
        }.buttonStyle(.plain).help("Auf der Leinwand zeigen")
    }
}
