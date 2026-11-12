import AppKit

/// La pàgina del permís de Configuració del Sistema, Privacitat i seguretat › Arxius i carpetes, on es dona a Warp Launch l'accés
/// a les dades de Warp (docs/fets-verificats.md, «Com es dona el permís»). Decisió 8 de l'autor (07/11/2026, docs/especificacio.md):
/// és l'única excepció a la guarda per obrir una pàgina de Configuració del Sistema, i només aquesta. La guarda en fixa les tres
/// línies i l'adreça, l'única de la llista (`nomesElServeiDelPermisObreConfiguracioDelSistema`). Només la crida el clic a
/// «Obre la configuració del sistema» (`EstatWarp.obrePermis`, el menú de la icona i el full d'importar).
///
/// L'adreça és la mateixa que fa servir macOS per al botó «Gestiona» de l'avís «Accés a les dades bloquejat» (`tccd` de macOS
/// 27.2); el tauler la declara com a seva (`legacyBundleIdentifier` de `SecurityPrivacyExtension.appex`). Llegit, no obert.
@MainActor
enum ServeiPermis {
    private static let adreca = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    static func obreArxiusICarpetes() {
        guard let url = URL(string: adreca) else { return }
        NSWorkspace.shared.open(url)
    }
}
