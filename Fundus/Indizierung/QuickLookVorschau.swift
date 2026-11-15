import AppKit
import Quartz

/// Große QuickLook-Vorschau (wie im Finder per Leertaste) für die ausgewählte Datei.
final class QuickLookVorschau: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookVorschau()
    private var urls: [URL] = []

    var sichtbar: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    func zeige(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func schliesse() {
        if sichtbar { QLPreviewPanel.shared()?.orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
