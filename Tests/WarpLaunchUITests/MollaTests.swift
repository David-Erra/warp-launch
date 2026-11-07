import Foundation
import Testing
@testable import WarpLaunchUI

// La decisió de la molla (obrir una fila aturant-s'hi arrossegant), sense AppKit ni rellotge.

private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let t0 = Date(timeIntervalSinceReferenceDate: 0)

@Suite struct MollaTests {
    @Test func sObreQuanHaPassatElRetard() {
        var estat = EstatMolla()
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        #expect(estat.decideix(ara: t0 + 0.3, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5) == .espera)
        #expect(estat.decideix(ara: t0 + 0.5, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5) == .obre(b))
    }

    /// El cursor fora de la fila (també fora de tota la barra lateral, on SwiftUI no avisa), o el botó amollat: s'atura.
    @Test func foraDeLaFilaOAmollatEsAtura() {
        var estat = EstatMolla()
        #expect(estat.decideix(ara: t0, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5)
            == .atura(.senseFila))
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        #expect(estat.decideix(ara: t0 + 1, cursorALaFila: false, botoPremut: true, filaEsDesti: nil, retard: 0.5)
            == .atura(.foraDeLaFila))
        #expect(estat.decideix(ara: t0 + 1, cursorALaFila: true, botoPremut: false, filaEsDesti: nil, retard: 0.5)
            == .atura(.amollat))
    }

    /// Una altra fila torna a començar el compte; la mateixa (`.active`), no.
    @Test func unaAltraFilaTornaAComencar() {
        var estat = EstatMolla()
        estat.entra(a, ara: t0, rectDeLaSessio: nil)
        estat.entra(b, ara: t0 + 0.4, rectDeLaSessio: nil)
        #expect(estat.decideix(ara: t0 + 0.6, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5) == .espera)
        estat.entra(b, ara: t0 + 0.8, rectDeLaSessio: nil)
        #expect(estat.decideix(ara: t0 + 0.9, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5) == .obre(b))
    }

    /// Moure's dins de la mateixa fila no torna a començar el compte: compta el temps que el cursor hi és, com macOS.
    @Test func moureSDinsDeLaFilaNoTornaAComencar() {
        var estat = EstatMolla()
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        estat.entra(b, ara: t0 + 0.3, rectDeLaSessio: nil)
        #expect(estat.decideix(ara: t0 + 0.5, cursorALaFila: true, botoPremut: true, filaEsDesti: nil, retard: 0.5) == .obre(b))
    }

    /// `.exiting` d'una altra fila no atura la que es compta (arriba després de l'`.entering` de la nova).
    @Test func sortirNomesDeLaQueEsCompta() {
        var estat = EstatMolla()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 28)
        estat.entra(b, ara: t0, rectDeLaSessio: rect)
        estat.surt(a)
        #expect(estat.fila == b)
        #expect(estat.rectDeLaSessio == rect)
        estat.surt(b)
        #expect(estat.fila == nil && estat.desDe == nil && estat.rectDeLaSessio == nil)
        estat.entra(a, ara: t0, rectDeLaSessio: nil)
        estat.surt()
        #expect(estat == EstatMolla())
    }

    // MARK: - Esc a mig arrossegament (pas 11)

    /// Amb el cursor quiet a la fila, Esc no avisa la fila, però AppKit li treu la marca de destinació: no s'obre mai,
    /// fins que s'amolla el botó.
    @Test func siLaFilaDeixaDeSerDestiNoSObre() {
        var estat = EstatMolla()
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        #expect(decideix(&estat, t0 + 0.1, desti: true) == .espera)
        #expect(estat.destiVist)
        #expect(decideix(&estat, t0 + 0.45, desti: false) == .espera)
        #expect(decideix(&estat, t0 + 0.5, desti: false) == .espera)
        #expect(decideix(&estat, t0 + 3, desti: false) == .espera)
        #expect(estat.decideix(ara: t0 + 3.05, cursorALaFila: true, botoPremut: false, filaEsDesti: false, retard: 0.5)
            == .atura(.amollat))
    }

    /// A la vora de la fila AppKit potser proposa inserir entre files: en tornar al mig, el compte torna a començar i
    /// s'obre (no s'atura per sempre, com a la prova 7c).
    @Test func siTornaASerDestiTornaAComptar() {
        var estat = EstatMolla()
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        #expect(decideix(&estat, t0 + 0.1, desti: true) == .espera)
        #expect(decideix(&estat, t0 + 0.2, desti: false) == .espera)
        #expect(decideix(&estat, t0 + 0.4, desti: true) == .espera)
        #expect(estat.desDe == t0 + 0.4)
        #expect(decideix(&estat, t0 + 0.6, desti: true) == .espera)
        #expect(decideix(&estat, t0 + 0.91, desti: true) == .obre(b))
    }

    /// Un parpelleig (fals un sol toc) no l'atura.
    @Test func unParpelleigNoLAtura() {
        var estat = EstatMolla()
        estat.entra(b, ara: t0, rectDeLaSessio: nil)
        #expect(decideix(&estat, t0 + 0.1, desti: true) == .espera)
        #expect(decideix(&estat, t0 + 0.15, desti: false) == .espera)
        #expect(decideix(&estat, t0 + 0.2, desti: true) == .espera)
        #expect(estat.perdutDesDe == nil)
        #expect(decideix(&estat, t0 + 0.5, desti: true) == .obre(b))
    }

    /// Si la fila no és mai la destinació, o no se sap, fa com abans: obre als 0,5 s.
    @Test func senseSenyalDeDestiFaComAbans() {
        for desti in [false, nil] as [Bool?] {
            var estat = EstatMolla()
            estat.entra(b, ara: t0, rectDeLaSessio: nil)
            #expect(decideix(&estat, t0 + 0.2, desti: desti) == .espera)
            #expect(decideix(&estat, t0 + 0.5, desti: desti) == .obre(b))
        }
    }

    /// El senyal és de cada fila: en passar a una altra, torna a fals.
    @Test func elSenyalEsDeCadaFila() {
        var estat = EstatMolla()
        estat.entra(a, ara: t0, rectDeLaSessio: nil)
        #expect(decideix(&estat, t0 + 0.1, desti: true) == .espera)
        estat.entra(b, ara: t0 + 0.2, rectDeLaSessio: nil)
        #expect(!estat.destiVist)
        #expect(decideix(&estat, t0 + 0.3, desti: false) == .espera)
        #expect(decideix(&estat, t0 + 0.71, desti: false) == .obre(b))
        estat.surt()
        #expect(estat == EstatMolla())
    }

    private func decideix(_ estat: inout EstatMolla, _ ara: Date, desti: Bool?) -> EstatMolla.Decisio {
        estat.decideix(ara: ara, cursorALaFila: true, botoPremut: true, filaEsDesti: desti, retard: 0.5)
    }
}
