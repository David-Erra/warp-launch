import Foundation
import WarpLaunchCore

// Dades de prova compartides per les proves del model de l'editor.

/// L'hora de l'ajust de Warp de debò (`AjustRestauracio`) a les proves (0.31.3): fixa, i un minut després de crear-la, perquè
/// els fitxers que s'hi escriuen no acabin de canviar. Les proves de l'escriptura prudent la mouen, sense esperar res. La
/// mateixa a `WarpLaunchCoreTests/AjustRestauracioTests.swift`.
final class RellotgeDeProva: @unchecked Sendable {
    private let pany = NSLock()
    private var valor = Date() + 60

    var ara: Date { get { pany.withLock { valor } } set { pany.withLock { valor = newValue } } }
    var funcio: @Sendable () -> Date { { [self] in ara } }

    /// Posa la data de modificació del fitxer a fa `segons`.
    func modificat(_ fitxer: URL, fa segons: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: ara - segons], ofItemAtPath: fitxer.path)
    }
}

extension ClaudePestanya {
    /// Dada de prova: `claude --dangerously-skip-permissions --effort ultracode`, continuant la conversa. Fins a la 0.27.3
    /// era la plantilla d'importar sense configuració; des de la 0.28.0 l'app ja no la té (D11, revisada el 07/11/2026). La mateixa a `WarpLaunchCoreTests/Fixtures.swift`.
    static let habituals = ClaudePestanya(esforc: "xhigh", ultracode: true, saltaPermisos: true)
}
