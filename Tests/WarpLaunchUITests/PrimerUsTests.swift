import Foundation
import Testing
import WarpLaunchCore
@testable import WarpLaunchUI

/// El primer ús (0.36.0): els tres passos de l'estat buit i l'enllaç a Configuració › General, amb uns ítems d'inici falsos.
/// Cap prova no toca els de debò ni obre la Configuració: l'enllaç només crida el que li passa l'app.
@MainActor
@Suite struct PrimerUsTests {
    @MainActor private final class Fals {
        var estat: ArrencadaSessio.Estat = .desactivada
        var crides: [String] = []
        var entorn: ArrencadaSessio.Entorn {
            ArrencadaSessio.Entorn(
                estat: { [unowned self] in estat },
                activa: { [unowned self] in crides.append("activa") },
                desactiva: { [unowned self] in crides.append("desactiva") },
                obreAjustos: { [unowned self] in crides.append("ajustos") })
        }
    }

    @Test func tresPassosEnOrdre() {
        #expect(PrimerUs.passos == [
            "Obre a Warp les finestres que vulguis recuperar.",
            "Importa-les amb «Importa de Warp…».",
            "Després d'un reinici, «Obre-ho tot a Warp…» les torna a obrir amb les seves sessions de Claude.",
        ])
        Idioma.$deProva.withValue("en") {
            #expect(PrimerUs.passos == [
                "Open the windows you want to get back in Warp.",
                "Import them with “Import from Warp…”.",
                "After a restart, “Open All in Warp…” reopens them with their Claude sessions.",
            ])
        }
    }

    /// Els passos diuen els botons pel nom que tenen en cada llengua (els de l'estat buit i el del menú).
    @Test func elsPassosDiuenElsBotonsPelSeuNom() {
        for llengua in Idioma.llenguesDisponibles {
            Idioma.$deProva.withValue(llengua) {
                let passos = PrimerUs.passos
                #expect(passos.count == 3)
                #expect(passos[1].contains(t("Importa de Warp…")), "\(llengua): \(passos[1])")
                #expect(passos[2].contains(t("Obre-ho tot a Warp…")), "\(llengua): \(passos[2])")
            }
        }
    }

    /// Amb l'interruptor desactivat i que es pot activar, l'enllaç hi és i només deixa la Configuració a «General»: no activa
    /// res (regla 3).
    @Test func lEnllacNomesHiPorta() {
        let f = Fals()
        var preparades = 0
        let primerUs = PrimerUs(arrencada: ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: nil),
                                preparaGeneral: { preparades += 1 })
        #expect(primerUs.mostraEnllacInici)
        primerUs.mostraGeneral()
        #expect(preparades == 1 && f.crides.isEmpty)
    }

    /// Ja activat (també pendent d'aprovar a macOS), amb l'app fora d'Aplicacions o amb una configuració de prova, l'enllaç no
    /// hi és, i el clic no fa res.
    @Test func senseEnllacSiJaHiEsONoEsPot() {
        for estat in [ArrencadaSessio.Estat.activada, .perAprovar] {
            let f = Fals()
            f.estat = estat
            var preparades = 0
            let primerUs = PrimerUs(arrencada: ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: nil),
                                    preparaGeneral: { preparades += 1 })
            #expect(!primerUs.mostraEnllacInici, "\(estat)")
            primerUs.mostraGeneral()
            #expect(preparades == 0, "\(estat)")
        }
        let f = Fals()
        let fora = PrimerUs(arrencada: ArrencadaSessio(entorn: f.entorn, motiuNoDisponible: "fora d'Aplicacions"),
                            preparaGeneral: {})
        #expect(!fora.mostraEnllacInici)
        let deProva = PrimerUs(arrencada: ArrencadaSessio(entorn: nil, motiuNoDisponible: "de prova"), preparaGeneral: {})
        #expect(!deProva.mostraEnllacInici)
    }
}
