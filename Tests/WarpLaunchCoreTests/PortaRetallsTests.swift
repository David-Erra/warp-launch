import Foundation
import Testing
@testable import WarpLaunchCore

// Pestanyes al porta-retalls (⌘C, ⌘X, ⌘V a l'editor) i enganxar-les a una finestra.

private let inici = "/Users/prova"

private func pestanya(_ n: Int, nom: String? = nil) -> Pestanya {
    Pestanya(id: uuid(n), titol: "p\(n)", carpeta: "\(inici)/GitHub/p\(n)", claude: ClaudePestanya(nom: nom))
}

@Suite struct PortaRetallsTests {
    @Test func lesPestanyesFanElViatge() throws {
        var rara = ClaudePestanya.habituals
        rara.nom = "Botiga"
        rara.model = "claude-opus-5-5"
        rara.settings = #"{"a":1}"#
        rara.controlRemot = ""
        rara.altres = ["--add-dir", "/tmp/x"]
        let pestanyes = [
            Pestanya(id: uuid(1), titol: "Botiga", carpeta: "\(inici)/GitHub/botiga", claude: rara),
            Pestanya(id: uuid(2), titol: "", carpeta: inici, claude: .nomesTerminal),
        ]
        let dades = try PortaRetalls.dades(pestanyes)
        #expect(PortaRetalls.pestanyes(de: dades, inici: inici) == pestanyes)
        // És el format del fitxer (per llegir-lo, si mai cal), amb la versió.
        let json = try #require(String(data: dades, encoding: .utf8))
        #expect(json.contains(#""versio" : 1"#))
    }

    @Test func elQueNoSonPestanyesNoEsPotEnganxar() throws {
        #expect(PortaRetalls.pestanyes(de: Data("claude --continue".utf8), inici: inici) == nil)
        #expect(PortaRetalls.pestanyes(de: Data(#"{"versio": 1, "finestres": []}"#.utf8), inici: inici) == nil)
        // D'una versió més nova del format: no (es perdrien camps). La mateixa amb la versió 1, sí.
        let dades = try PortaRetalls.dades([pestanya(1)])
        let text = try #require(String(data: dades, encoding: .utf8))
        #expect(text.contains(#""versio" : 1"#))
        let nova = Data(text.replacingOccurrences(of: #""versio" : 1"#, with: #""versio" : 99"#).utf8)
        #expect(PortaRetalls.pestanyes(de: nova, inici: inici) == nil)
        #expect(PortaRetalls.pestanyes(de: dades, inici: inici) == [pestanya(1)])
        #expect(PortaRetalls.pestanyes(de: Data(), inici: inici) == nil)
    }

    @Test func enganxarCopiesIRetallades() {
        var c = Configuracio(finestres: [
            Finestra(id: uuid(1), nom: "a", pestanyes: [pestanya(11, nom: "Botiga"), pestanya(12)]),
            Finestra(id: uuid(2), nom: "b", pestanyes: [pestanya(21), pestanya(22)]),
        ])
        let ids = IdsDeProva()
        // Copiades (encara hi són): còpies, amb id nou i sense nom fix de sessió, després de p21.
        let copies = c.enganxa([pestanya(11, nom: "Botiga"), pestanya(12)], a: uuid(2), despresDe: uuid(21), nouId: ids.nou)
        #expect(c.finestres[1].pestanyes.map(\.titol) == ["p21", "p11", "p12", "p22"])
        #expect(copies == [c.finestres[1].pestanyes[1].id, c.finestres[1].pestanyes[2].id])
        #expect(!copies.contains(uuid(11)) && !copies.contains(uuid(12)))
        #expect(c.finestres[1].pestanyes[1].claude.nom == nil)
        #expect(c.finestres[0].pestanyes[0].claude.nom == "Botiga", "l'original no canvia")

        // Retallades (ja no hi són): tornen tal com eren, al final si `despresDe` no hi és.
        c.eliminaPestanyes([uuid(11)])
        #expect(c.enganxa([pestanya(11, nom: "Botiga")], a: uuid(2), despresDe: uuid(99), nouId: ids.nou) == [uuid(11)])
        #expect(c.finestres[1].pestanyes.last == pestanya(11, nom: "Botiga"))

        // La mateixa pestanya dues vegades al porta-retalls: la segona és una còpia.
        c.eliminaPestanyes([uuid(11)])
        let dues = c.enganxa([pestanya(11), pestanya(11)], a: uuid(1), nouId: ids.nou)
        #expect(dues.first == uuid(11) && dues.count == 2 && dues[1] != uuid(11))
        #expect(Set(c.finestres.flatMap(\.pestanyes).map(\.id)).count == c.finestres.flatMap(\.pestanyes).count)

        let abans = c
        #expect(c.enganxa([pestanya(31)], a: uuid(99), nouId: ids.nou).isEmpty)
        #expect(c == abans)
    }

    /// Una pestanya d'una altra configuració (o d'abans de tornar a importar) té un id que no hi és, però el seu nom
    /// fix de sessió el pot tenir una altra pestanya: entra sense, com una còpia.
    @Test func capNomDeSessioRepetit() {
        var c = Configuracio(finestres: [Finestra(id: uuid(1), nom: "a", pestanyes: [pestanya(11, nom: "Botiga")])])
        let ids = IdsDeProva()
        let enganxades = c.enganxa([pestanya(31, nom: "Botiga"), pestanya(32, nom: "Planta"), pestanya(33, nom: "Planta")],
                                   a: uuid(1), nouId: ids.nou)
        #expect(enganxades == [uuid(31), uuid(32), uuid(33)], "conserven l'id: no hi eren")
        #expect(c.finestres[0].pestanyes.map(\.claude.nom) == ["Botiga", nil, "Planta", nil])
    }
}

@Suite struct ArrossegarPortaRetallsTests {
    @Test func portaLOrigenIElsId() throws {
        let dades = try PortaRetalls.dades([pestanya(1), pestanya(2)], origen: uuid(7))
        let llegides = try #require(PortaRetalls.origenIIds(de: dades))
        #expect(llegides.origen == uuid(7))
        #expect(llegides.ids == [uuid(1), uuid(2)])
        #expect(PortaRetalls.pestanyes(de: dades, inici: inici) == [pestanya(1), pestanya(2)], "el format del porta-retalls")
        #expect(PortaRetalls.origenIIds(de: Data("claude --continue".utf8)) == nil)
        let dues = try Configuracio(finestres: [
            Finestra(id: uuid(8), nom: "x", pestanyes: [pestanya(1)]),
            Finestra(id: uuid(9), nom: "y", pestanyes: [pestanya(2)]),
        ]).json()
        #expect(PortaRetalls.origenIIds(de: dues) == nil, "dues finestres: no surt de cap arrossegament")
        let a = try #require(PortaRetalls.origenIIds(de: PortaRetalls.dades([pestanya(1)])))
        let b = try #require(PortaRetalls.origenIIds(de: PortaRetalls.dades([pestanya(1)])))
        #expect(a.origen != b.origen, "al porta-retalls, cada cop un de diferent")
    }
}
