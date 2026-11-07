import AppKit

/// Mostrar un fitxer al Finder: l'única crida de l'app a l'espai de treball del sistema (la prova de guarda ho
/// vigila). Selecciona el fitxer en una finestra del Finder; no l'obre ni executa res.
public enum Finder {
    @MainActor
    public static func mostra(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
