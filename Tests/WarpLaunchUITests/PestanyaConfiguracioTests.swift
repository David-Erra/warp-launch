import AppKit
import Testing
@testable import WarpLaunchUI

// Les pestanyes de la Configuració (settings.md de mac-design). La disposició (la mida de cada pestanya, la finestra i el
// desplaçament) no es pot provar aquí: les proves no creen vistes ni finestres d'AppKit (prova de guarda). La revisa en
// David a la pantalla.

@MainActor
@Suite struct PestanyaConfiguracioTests {
    @Test func generalPrimerIDespresLesPestanyesNoves() {
        #expect(PestanyaConfiguracio.allCases == [.general, .pestanyesNoves])
        #expect(PestanyaConfiguracio.allCases.map(\.titol) == ["General", "Pestanyes noves"])
        // settings.md: de dues a sis pestanyes; amb més, una barra lateral.
        #expect((2...6).contains(PestanyaConfiguracio.allCases.count))
    }

    /// Un nom que no existeix deixaria la pestanya sense icona a la barra d'eines, i no es veuria fins a obrir l'app.
    @Test func cadaPestanyaTeUnSimbolDiferentQueExisteix() {
        let simbols = PestanyaConfiguracio.allCases.map(\.simbol)
        #expect(simbols.first == "gearshape")
        #expect(Set(simbols).count == simbols.count)
        for simbol in simbols {
            #expect(NSImage(systemSymbolName: simbol, accessibilityDescription: nil) != nil, "\(simbol)")
        }
    }

    @Test func midaDeLaNorma() {
        #expect(VistaConfiguracio.amplada == 520)
        #expect(VistaConfiguracio.alcadaMaxima == 640)
    }
}
