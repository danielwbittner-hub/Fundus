import SwiftUI

/// Ein Tastaturkürzel: Basistaste + Modifikatoren. `aktiv == false` = nicht belegt.
struct Kuerzel: Codable, Equatable {
    var taste: String            // z. B. "t", "0", "+", "return", "space"
    var command = true
    var shift = false
    var option = false
    var control = false
    var aktiv = true

    var modifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }
        if shift { m.insert(.shift) }
        if option { m.insert(.option) }
        if control { m.insert(.control) }
        return m
    }
    var keyEquivalent: KeyEquivalent {
        switch taste {
        case "return": return .return
        case "space", " ": return .space
        case "delete": return .delete
        default:
            if let c = taste.first { return KeyEquivalent(c) }
            return KeyEquivalent("?")
        }
    }
    var belegt: Bool { aktiv && !taste.isEmpty }

    private var anzeigeTaste: String {
        switch taste {
        case "return": return "↩"
        case "space", " ": return "Leer"
        case "delete": return "⌫"
        case "+": return "+"
        case "-": return "–"
        default: return taste.uppercased()
        }
    }
    var anzeige: String {
        guard belegt else { return "—" }
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + anzeigeTaste
    }
}

/// Alle per Tastatur ansteuerbaren Werkzeuge/Befehle.
enum Werkzeugbefehl: String, CaseIterable, Identifiable {
    case schnellsuche
    case textfeld, zettel, link, ordner, bereich, verbinden
    case neueLeinwand
    case vergroessern, verkleinern, einpassen, zoomReset
    case widerrufen, wiederholen
    case gesundheit, uebersicht

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .schnellsuche: return "Schnell finden"
        case .gesundheit: return "Gesundheits-Check"
        case .textfeld: return "Textfeld"
        case .zettel: return "Notizzettel"
        case .link: return "Website-Link"
        case .ordner: return "Mappe"
        case .bereich: return "Bereich"
        case .verbinden: return "Verbinden"
        case .neueLeinwand: return "Neue Leinwand"
        case .vergroessern: return "Vergrößern"
        case .verkleinern: return "Verkleinern"
        case .einpassen: return "Alles einpassen"
        case .zoomReset: return "Zoom zurücksetzen (100 %)"
        case .widerrufen: return "Widerrufen"
        case .wiederholen: return "Wiederholen"
        case .uebersicht: return "Tastaturbefehle anzeigen"
        }
    }
    var symbol: String {
        switch self {
        case .schnellsuche: return "magnifyingglass"
        case .gesundheit: return "stethoscope"
        case .textfeld: return "character.textbox"
        case .zettel: return "note.text"
        case .link: return "globe"
        case .ordner: return "folder.badge.plus"
        case .bereich: return "rectangle.dashed"
        case .verbinden: return "point.topleft.down.to.point.bottomright.curvepath"
        case .neueLeinwand: return "square.stack.3d.up"
        case .vergroessern: return "plus.magnifyingglass"
        case .verkleinern: return "minus.magnifyingglass"
        case .einpassen: return "arrow.up.left.and.down.right.magnifyingglass"
        case .zoomReset: return "1.magnifyingglass"
        case .widerrufen: return "arrow.uturn.backward"
        case .wiederholen: return "arrow.uturn.forward"
        case .uebersicht: return "keyboard"
        }
    }
    var gruppe: String {
        switch self {
        case .schnellsuche: return "Finden"
        case .textfeld, .zettel, .link, .ordner, .bereich, .verbinden: return "Objekte anlegen"
        case .neueLeinwand: return "Leinwände"
        case .vergroessern, .verkleinern, .einpassen, .zoomReset: return "Ansicht"
        case .widerrufen, .wiederholen: return "Bearbeiten"
        case .gesundheit, .uebersicht: return "Hilfe"
        }
    }
    static let gruppen = ["Finden", "Objekte anlegen", "Leinwände", "Ansicht", "Bearbeiten", "Hilfe"]

    var standard: Kuerzel {
        switch self {
        case .schnellsuche: return Kuerzel(taste: "k")
        case .textfeld: return Kuerzel(taste: "t")
        case .zettel: return Kuerzel(taste: "t", shift: true)
        case .link: return Kuerzel(taste: "l")
        case .ordner: return Kuerzel(taste: "o", shift: true)
        case .bereich: return Kuerzel(taste: "b", shift: true)
        case .verbinden: return Kuerzel(taste: "u")
        case .neueLeinwand: return Kuerzel(taste: "n")
        case .vergroessern: return Kuerzel(taste: "+")
        case .verkleinern: return Kuerzel(taste: "-")
        case .einpassen: return Kuerzel(taste: "0")
        case .zoomReset: return Kuerzel(taste: "0", shift: true)
        case .widerrufen: return Kuerzel(taste: "z")
        case .wiederholen: return Kuerzel(taste: "z", shift: true)
        case .gesundheit: return Kuerzel(taste: "j", shift: true)
        case .uebersicht: return Kuerzel(taste: "/")
        }
    }
}

/// Speichert die (ggf. angepassten) Kürzel und verwaltet die Aufnahme neuer Tasten.
@MainActor
final class Tastenkuerzel: ObservableObject {
    @Published private var eigene: [String: Kuerzel] = [:]
    @Published var aufnahme: Werkzeugbefehl? = nil     // Befehl, der gerade neu belegt wird

    private let schluessel = "fundus.tastenkuerzel"

    init() { laden() }

    func kuerzel(_ b: Werkzeugbefehl) -> Kuerzel { eigene[b.rawValue] ?? b.standard }
    func istEigen(_ b: Werkzeugbefehl) -> Bool { eigene[b.rawValue] != nil }

    /// Belegt einen Befehl neu; ein evtl. doppelt belegter anderer Befehl wird frei.
    func setze(_ b: Werkzeugbefehl, _ k: Kuerzel) {
        for andere in Werkzeugbefehl.allCases where andere != b {
            let vorhanden = kuerzel(andere)
            if vorhanden.belegt, vorhanden.taste == k.taste, vorhanden.modifiers == k.modifiers {
                eigene[andere.rawValue] = Kuerzel(taste: "", command: false, aktiv: false)
            }
        }
        eigene[b.rawValue] = k
        speichern()
    }
    func loesche(_ b: Werkzeugbefehl) {
        eigene[b.rawValue] = Kuerzel(taste: "", command: false, aktiv: false)
        speichern()
    }
    func zuruecksetzen(_ b: Werkzeugbefehl) { eigene[b.rawValue] = nil; speichern() }
    func allesZuruecksetzen() { eigene.removeAll(); speichern() }

    private func speichern() {
        if let d = try? JSONEncoder().encode(eigene) { UserDefaults.standard.set(d, forKey: schluessel) }
    }
    private func laden() {
        if let d = UserDefaults.standard.data(forKey: schluessel),
           let m = try? JSONDecoder().decode([String: Kuerzel].self, from: d) { eigene = m }
    }
}

/// Wendet ein Kürzel auf einen Button an – oder nichts, wenn es nicht belegt ist.
struct KuerzelTaste: ViewModifier {
    let k: Kuerzel
    func body(content: Content) -> some View {
        if k.belegt {
            content.keyboardShortcut(k.keyEquivalent, modifiers: k.modifiers)
        } else {
            content
        }
    }
}
extension View {
    func kuerzel(_ k: Kuerzel) -> some View { modifier(KuerzelTaste(k: k)) }
}
