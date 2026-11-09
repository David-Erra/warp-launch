import Foundation
import Testing
import WarpLaunchCore

/// D3: quan una arrencada és la de l'inici de sessió.
@Suite struct InicDeSessioTests {
    @Test(arguments: [
        (true, 10_000.0, true, true),     // macOS diu que és un element d'inici
        (false, 120.0, true, true),       // el Mac s'acaba d'encendre
        (false, 10_000.0, true, false),   // oberta a mà, amb el Mac encès fa estona
        (true, 60.0, false, false),       // no és als ítems d'inici: mai
    ])
    func decideix(comElement: Bool, segons: Double, registrada: Bool, esperat: Bool) {
        #expect(InicDeSessio.es(comElementDInici: comElement, segonsEncesa: segons, registrada: registrada,
                                reobertaPerActualitzacio: false) == esperat)
    }

    /// Reoberta per una actualització, mai: tampoc dins dels 600 s ni com a element d'inici.
    @Test(arguments: [(true, 10_000.0), (false, 120.0), (true, 60.0), (false, InicDeSessio.marge - 1)])
    func reobertaPerActualitzacioMai(comElement: Bool, segons: Double) {
        #expect(!InicDeSessio.es(comElementDInici: comElement, segonsEncesa: segons, registrada: true, reobertaPerActualitzacio: true))
    }
}
