import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// «Copia el diagnòstic», a la Configuració (pla A4, 0.30.0): amb un diagnòstic fals i un porta-retalls fals.

@MainActor
@Suite struct CopiaDiagnosticTests {
    private nonisolated static func informe(anonimitzat: Bool) -> InformeDiagnostic {
        InformeDiagnostic(versio: "Warp Launch x", sistema: "macOS de prova", anonimitzat: anonimitzat, comprovacions: [
            Comprovacio(.terminalsWarp, .be, "bé"),
            Comprovacio(.versioWarp, .avis, "no provada"),
            Comprovacio(.versioClaude, .avis, "no provada"),
        ])
    }

    /// L'app demana el text de les actualitzacions al fil principal des del diagnòstic: mentre es copia, el fil principal ha de quedar lliure.
    @Test func elDiagnosticPotPreguntarAlFilPrincipal() async {
        let diagnostic: @Sendable (Bool) -> InformeDiagnostic = { anonimitzat in
            var informe = Self.informe(anonimitzat: anonimitzat)
            informe.actualitzacions = DispatchQueue.main.sync { MainActor.assumeIsolated { "des del fil principal" } }
            return informe
        }
        let c = CopiaDiagnostic(diagnostic: diagnostic, escriu: { _ in })
        await c.copia(anonimitzat: false)
        #expect(c.copiat != nil)
        #expect(!c.calculant)
    }

    @Test func copiaLAnonimitzatOElComplet() async {
        let demanats = Demanats()
        let portaRetalls = PortaRetallsFals()
        let copia = CopiaDiagnostic(diagnostic: { demanats.afegeix($0); return Self.informe(anonimitzat: $0) }, escriu: { portaRetalls.textos.append($0) })
        #expect(copia.copiat == nil && !copia.calculant)

        await copia.copia(anonimitzat: true)
        #expect(demanats.valors == [true])
        #expect(portaRetalls.textos == [Self.informe(anonimitzat: true).text])
        #expect(copia.copiat == "Copiat (anonimitzat): 1 bé, 2 avisos, 0 errors.")
        #expect(!copia.calculant)

        await copia.copia(anonimitzat: false)
        #expect(demanats.valors == [true, false])
        #expect(portaRetalls.textos.last?.contains("Not anonymized") == true)
        #expect(copia.copiat == "Copiat (complet): 1 bé, 2 avisos, 0 errors.")
    }
}

/// Un porta-retalls fals: cap prova no toca el de debò.
@MainActor
private final class PortaRetallsFals {
    var textos: [String] = []
}

/// Quins diagnòstics s'han demanat (des d'un altre fil).
private final class Demanats: @unchecked Sendable {
    private let pany = NSLock()
    private var llista: [Bool] = []

    func afegeix(_ valor: Bool) { pany.withLock { llista.append(valor) } }
    var valors: [Bool] { pany.withLock { llista } }
}
