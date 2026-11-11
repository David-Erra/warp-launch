import Foundation
import Testing
import WarpLaunchCore
@testable import WarpLaunchUI

/// «Idioma», a la Configuració (docs/disseny.md, secció 12, F4), amb unes preferències falses: cap prova no llegeix ni escriu
/// cap domini de preferències de debò (l'únic que ho fa és `ServeiIdioma`, a l'app).
@MainActor
@Suite struct SelectorIdiomaTests {
    @MainActor private final class Fals {
        /// `AppleLanguages` del domini global (el Mac).
        var delSistema: [String]
        /// `AppleLanguages` del domini de l'app, o res si no hi és.
        var deLApp: [String]?
        var desats: [[String]?] = []

        init(delSistema: [String] = ["ca-ES", "en-US"], deLApp: [String]? = nil) {
            self.delSistema = delSistema
            self.deLApp = deLApp
        }

        var entorn: SelectorIdioma.Entorn {
            SelectorIdioma.Entorn(delSistema: { [self] in delSistema },
                                  deLApp: { [self] in deLApp },
                                  desa: { [self] in
                                      desats.append($0)
                                      deLApp = $0
                                  })
        }
    }

    /// Sense `AppleLanguages` a l'app, la del sistema, amb el nom de la llengua que surt (en la llengua de l'app). Les llengües,
    /// les dels textos, amb el nom en elles mateixes. Sense cap canvi, cap nota.
    @Test func senseLaPreferenciaDeLAppMarcaLaDelSistema() {
        let f = Fals()
        let s = SelectorIdioma(entorn: f.entorn, disponibles: ["ca", "en"], actual: "ca")
        #expect(s.tria == .sistema)
        #expect(s.sistema.text == "El del sistema (català)")
        #expect(s.llengues.map(\.text) == ["Català", "English"])
        #expect(s.llengues.map(\.tria) == [.llengua("ca"), .llengua("en")])
        #expect(s.nota == nil)
        #expect(f.desats.isEmpty)
    }

    /// Amb `AppleLanguages` a les preferències de l'app, la marca, també amb una regió (`en-GB`). L'opció del sistema diu la del
    /// Mac, no la de l'app.
    @Test func ambLaPreferenciaDeLAppLaMarca() {
        for preferencia in [["en"], ["en-GB"], ["en", "ca"]] {
            let s = SelectorIdioma(entorn: Fals(deLApp: preferencia).entorn, disponibles: ["ca", "en"], actual: "en")
            #expect(s.tria == .llengua("en"), "\(preferencia)")
            #expect(s.sistema.text == "El del sistema (català)")
            #expect(s.nota == nil)
        }
        // Una llengua sense textos surt en anglès (la de reserva), i és la que es marca.
        #expect(SelectorIdioma(entorn: Fals(deLApp: ["de"]).entorn, disponibles: ["ca", "en"], actual: "en").tria == .llengua("en"))
        // Una llista buida és com si no hi fos.
        #expect(SelectorIdioma(entorn: Fals(deLApp: []).entorn, disponibles: ["ca", "en"], actual: "ca").tria == .sistema)
    }

    /// Triar una llengua la desa com a `[codi]`; triar la del sistema esborra la clau. Si la llengua canvia, la nota diu que serà
    /// la propera vegada que s'obri l'app.
    @Test func desaLaTriaIAvisaQueCanviaraEnTornarAObrir() {
        let f = Fals()
        let s = SelectorIdioma(entorn: f.entorn, disponibles: ["ca", "en"], actual: "ca")
        s.posa(.llengua("en"))
        #expect(f.desats == [["en"]])
        #expect(s.tria == .llengua("en"))
        #expect(s.nota == "L'idioma canviarà la propera vegada que obris l'app.")
        // La mateixa, cap escriptura més.
        s.posa(.llengua("en"))
        #expect(f.desats == [["en"]])
        s.posa(.sistema)
        #expect(f.desats == [["en"], nil])
        #expect(s.tria == .sistema && s.nota == nil)
        // Triar la que ja es veu la desa, i no hi ha cap nota.
        s.posa(.llengua("ca"))
        #expect(f.desats == [["en"], nil, ["ca"]])
        #expect(s.nota == nil)
        // Una llengua sense textos no es desa.
        s.posa(.llengua("de"))
        #expect(f.desats == [["en"], nil, ["ca"]] && s.tria == .llengua("ca"))
    }

    /// Amb la llengua de l'app triada, tornar a la del sistema avisa si el sistema és en una altra.
    @Test func tornarALaDelSistemaTambeAvisa() {
        let f = Fals(delSistema: ["ca-ES"], deLApp: ["en"])
        let s = SelectorIdioma(entorn: f.entorn, disponibles: ["ca", "en"], actual: "en")
        #expect(s.tria == .llengua("en") && s.nota == nil)
        s.posa(.sistema)
        #expect(f.desats == [nil])
        #expect(s.llenguaTriada == "ca")
        #expect(s.nota == "L'idioma canviarà la propera vegada que obris l'app.")
    }

    /// Una llengua nova (una carpeta `.lproj` més) surt sola, amb el seu nom i en ordre alfabètic del nom: no cal tocar el codi.
    /// L'opció del sistema, amb una llengua que no té textos, diu la de reserva.
    @Test func lesLlenguesSurtenDeLesCarpetes() {
        let totes = ["ca", "de", "en", "es", "fr", "it", "ja", "ko", "pt-BR", "zh-Hans"]
        let s = SelectorIdioma(entorn: Fals(delSistema: ["ru-RU"]).entorn, disponibles: totes, actual: "en")
        #expect(s.llengues.map(\.text) == ["Català", "Deutsch", "English", "Español", "Français", "Italiano",
                                           "Português (Brasil)", "한국어", "日本語", "简体中文"])
        #expect(Set(s.llengues.map(\.tria)) == Set(totes.map { .llengua($0) }))
        #expect(s.llenguaDelSistema == "en")
        #expect(s.sistema.text == "El del sistema (anglès)")
        let pt = SelectorIdioma(entorn: Fals(delSistema: ["pt-PT"]).entorn, disponibles: totes, actual: "en")
        #expect(pt.llenguaDelSistema == "pt-BR")
    }

    /// En anglès, l'opció del sistema i la nota.
    @Test func enAngles() {
        Idioma.$deProva.withValue("en") {
            let f = Fals(delSistema: ["ca-ES"])
            let s = SelectorIdioma(entorn: f.entorn, disponibles: ["ca", "en"], actual: "en")
            #expect(s.sistema.text == "System Language (Catalan)")
            #expect(s.nota == "The language will change the next time you open the app.")
            #expect(s.llengues.map(\.text) == ["Català", "English"])
        }
    }
}
