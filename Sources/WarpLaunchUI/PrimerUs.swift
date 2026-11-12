import Foundation
import WarpLaunchCore

/// El primer ús (0.36.0, docs/disseny.md, secció 14): sense configuració, l'estat buit de l'editor diu en tres passos què fa
/// l'app i què cal fer, amb els botons de sempre («Importa de Warp…» i «Comença en blanc»). Si l'app encara no s'obre sola en
/// iniciar sessió i es pot activar, hi ha un enllaç a Configuració › General, on hi ha l'interruptor (D3). L'enllaç només hi
/// porta: l'interruptor el toca l'usuari (regla 3).
@MainActor
public struct PrimerUs {
    /// Els tres passos, en ordre: a Warp, a l'app i després d'un reinici.
    public static var passos: [String] {
        [
            t("Obre a Warp les finestres que vulguis recuperar."),
            t("Importa-les amb «Importa de Warp…»."),
            t("Després d'un reinici, «Obre-ho tot a Warp…» les torna a obrir amb les seves sessions de Claude."),
        ]
    }

    let arrencada: ArrencadaSessio
    let preparaGeneral: @MainActor () -> Void

    /// - Parameters:
    ///   - arrencada: «Obre Warp Launch en iniciar sessió», el de la Configuració.
    ///   - preparaGeneral: deixa la Configuració a «General» (l'app hi tria la pestanya); la vista l'obre just després.
    public init(arrencada: ArrencadaSessio, preparaGeneral: @escaping @MainActor () -> Void) {
        self.arrencada = arrencada
        self.preparaGeneral = preparaGeneral
    }

    /// L'enllaç: amb l'interruptor encara desactivat i que es pot activar. Amb una configuració de prova o l'app fora
    /// d'Aplicacions, no: l'interruptor no es podria activar (`ArrencadaSessio.motiuNoDisponible`).
    public var mostraEnllacInici: Bool { !arrencada.activada && arrencada.editable }

    /// El clic de l'enllaç, abans d'obrir la Configuració. Si l'enllaç no hi ha de ser, res.
    public func mostraGeneral() {
        guard mostraEnllacInici else { return }
        preparaGeneral()
    }
}
