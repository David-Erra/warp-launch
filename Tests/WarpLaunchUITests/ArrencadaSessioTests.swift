import Foundation
import Testing
import WarpLaunchCore
@testable import WarpLaunchUI

/// L'interruptor «Obre Warp Launch en iniciar sessió» (D3), amb uns ítems d'inici falsos: cap prova toca els de debò.
@MainActor
@Suite struct ArrencadaSessioTests {
    @MainActor private final class Fals {
        var estat: ArrencadaSessio.Estat = .desactivada
        var crides: [String] = []
        var falla: (any Error)?
        var entorn: ArrencadaSessio.Entorn {
            ArrencadaSessio.Entorn(
                estat: { [unowned self] in estat },
                activa: { [unowned self] in
                    crides.append("activa")
                    if let falla { throw falla }
                    estat = .activada
                },
                desactiva: { [unowned self] in
                    crides.append("desactiva")
                    if let falla { throw falla }
                    estat = .desactivada
                },
                obreAjustos: { [unowned self] in crides.append("ajustos") })
        }
    }

    private struct NoEsPot: LocalizedError {
        var errorDescription: String? { "Operació no permesa" }
    }

    @Test func lActivaILaDesactiva() {
        let f = Fals()
        let a = ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: nil)
        #expect(!a.activada && a.editable)
        a.posa(true)
        #expect(a.activada && a.obreSola && f.crides == ["activa"])
        a.posa(true)
        #expect(f.crides == ["activa"], "ja ho era")
        a.posa(false)
        #expect(!a.activada && f.crides == ["activa", "desactiva"])
    }

    /// Fora d'Aplicacions no es pot activar; si ja ho era (d'una altra còpia), sí que es pot desactivar.
    @Test func ambUnMotiuNomesEsPotDesactivar() {
        let f = Fals()
        let a = ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: "fora d'Aplicacions")
        #expect(!a.editable)
        a.posa(true)
        #expect(f.crides.isEmpty && !a.activada)
        f.estat = .activada
        a.actualitza()
        #expect(a.editable)
        a.posa(false)
        #expect(f.crides == ["desactiva"] && !a.activada)
    }

    @Test func unErrorEsDiu() {
        let f = Fals()
        f.falla = NoEsPot()
        let a = ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: nil)
        a.posa(true)
        #expect(a.error == "No s'ha pogut activar: Operació no permesa")
        #expect(!a.activada)
        f.falla = nil
        a.posa(true)
        #expect(a.error == nil && a.activada)
    }

    /// Pendent d'aprovar a Configuració del Sistema compta com a activada (l'interruptor la pot treure).
    @Test func perAprovarEsActivada() {
        let f = Fals()
        f.estat = .perAprovar
        let a = ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: nil)
        #expect(a.activada && a.estat == .perAprovar)
        #expect(!a.obreSola, "macOS no l'obrirà sola: no ha de sortir el full per l'hora (revisió)")
        a.obreAjustos()
        #expect(f.crides == ["ajustos"])
    }

    /// Amb una configuració de prova, cap accés als ítems d'inici.
    @Test func senseEntornNoFaRes() {
        let a = ArrencadaSessio(entorn: nil, motiuNoDisponible: "Amb una configuració de prova, l'app no s'obre sola.")
        #expect(!a.editable && !a.activada)
        a.posa(true)
        #expect(!a.activada && a.error == nil)
    }
}
