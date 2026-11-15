import SwiftUI

/// ⌘K-Schnellsuche: findet Objekte über ALLE Leinwände hinweg und springt
/// direkt dorthin (wechselt bei Bedarf die Leinwand und zentriert die Karte).
struct Schnellsuche: View {
    @EnvironmentObject var app: AppModell
    @FocusState private var fokus: Bool
    @State private var markiert = 0   // hervorgehobener Treffer (Pfeiltasten)

    private var treffer: [GlobalTreffer] { app.paletteTreffer }

    var body: some View {
        ZStack(alignment: .top) {
            // Abdunkeln – Klick daneben schließt.
            Color.black.opacity(0.35).ignoresSafeArea()
                .onTapGesture { app.zeigePalette = false }

            VStack(spacing: 0) {
                feld
                if !treffer.isEmpty {
                    Divider().opacity(0.4)
                    liste
                } else if !app.paletteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Keine Treffer")
                        .font(Design.grotesk(12.5)).foregroundStyle(Design.gedaempft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 16)
                }
            }
            .frame(width: 560)
            .environment(\.colorScheme, .dark)
            .background(Design.paneel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
            .padding(.top, 96)
        }
        .onAppear { markiert = 0; DispatchQueue.main.async { fokus = true } }
        .onChange(of: app.paletteTreffer) { _, _ in markiert = 0 }
    }

    private var feld: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(Design.neonCyan)
            TextField("Über alle Leinwände finden – Name, Inhalt, Schlagwort …", text: $app.paletteText)
                .textFieldStyle(.plain).font(Design.grotesk(17))
                .foregroundStyle(.white)
                .focused($fokus)
                .onSubmit { waehleMarkierten() }
                .onKeyPress(.downArrow) { markiert = min(markiert + 1, max(0, treffer.count - 1)); return .handled }
                .onKeyPress(.upArrow) { markiert = max(markiert - 1, 0); return .handled }
                .onKeyPress(.escape) { app.zeigePalette = false; return .handled }
            if !app.paletteText.isEmpty {
                Button { app.paletteText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Design.paneelInhalt)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
    }

    private var liste: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(Array(treffer.enumerated()), id: \.element.id) { i, t in
                        zeile(t, hervor: i == markiert)
                            .id(i)
                            .onTapGesture { app.springeZu(t) }
                            .onHover { if $0 { markiert = i } }
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(treffer.count) * 50 + 4, 360))
            .onChange(of: markiert) { _, neu in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(neu, anchor: .center) } }
        }
    }

    private func zeile(_ t: GlobalTreffer, hervor: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(t)).font(.system(size: 14, weight: .medium))
                .foregroundStyle(Design.neon).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(Design.grotesk(14, gewicht: .medium)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 9))
                    Text(t.boardName).lineLimit(1)
                    if !t.tags.isEmpty {
                        Text("· \(t.tags)").lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(Design.grotesk(10.5)).foregroundStyle(Design.paneelInhalt.opacity(0.8))
            }
            Spacer(minLength: 0)
            if t.boardID != app.aktivBoard {
                Text("wechseln").font(Design.grotesk(9.5, gewicht: .semibold))
                    .foregroundStyle(Design.neonCyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Design.neonCyan.opacity(0.14)))
            }
            Image(systemName: "return").font(.system(size: 11))
                .foregroundStyle(Design.neonCyan).opacity(hervor ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hervor ? Color.white.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
    }

    private func symbol(_ t: GlobalTreffer) -> String {
        switch t.kategorie {
        case .weblink: return "globe"
        case .ordnerExtern: return "folder.fill"
        default: return t.kategorie.symbol
        }
    }

    private func waehleMarkierten() {
        guard markiert < treffer.count else {
            if let erste = treffer.first { app.springeZu(erste) }
            return
        }
        app.springeZu(treffer[markiert])
    }
}
