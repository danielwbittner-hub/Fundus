import Foundation

/// Führt einen `Process` mit Zeitlimit aus. Hängt der Prozess (z. B. InDesign mit
/// einem Modaldialog, oder `unzip` auf einer kaputten Datei), wird er nach `frist`
/// Sekunden hart beendet – statt den aufrufenden Thread dauerhaft zu blockieren.
enum Prozesslauf {
    /// Startet `p`, wartet höchstens `frist` Sekunden. Rückgabe: true, wenn der
    /// Prozess regulär mit Status 0 endete; false bei Fehler, Timeout oder Status ≠ 0.
    @discardableResult
    static func fuehre(_ p: Process, frist: TimeInterval) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in sem.signal() }
        do { try p.run() } catch { return false }
        if sem.wait(timeout: .now() + frist) == .timedOut {
            p.terminate()
            _ = sem.wait(timeout: .now() + 3)   // kurz auf das Beenden warten
            return false
        }
        return p.terminationStatus == 0
    }
}

/// Einfache asynchrone Drossel (zählender Semaphor) – begrenzt, wie viele schwere
/// Indizierungs-/Vorschau-Jobs gleichzeitig laufen, damit ein Massenimport nicht
/// hunderte Prozesse/Threads auf einmal startet.
actor AsyncDrossel {
    private let maximum: Int
    private var aktiv = 0
    private var warteschlange: [CheckedContinuation<Void, Never>] = []

    init(_ maximum: Int) { self.maximum = max(1, maximum) }

    func nimm() async {
        if aktiv < maximum { aktiv += 1; return }
        await withCheckedContinuation { warteschlange.append($0) }
    }

    func gib() {
        if warteschlange.isEmpty { aktiv = max(0, aktiv - 1) }
        else { warteschlange.removeFirst().resume() }
    }

    /// Bequem: Arbeit gedrosselt ausführen (immer wieder freigeben, auch bei Fehler).
    func mit<T>(_ arbeit: () async -> T) async -> T {
        await nimm()
        defer { gib() }
        return await arbeit()
    }
}
