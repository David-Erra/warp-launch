import Foundation
import Testing
@testable import WarpLaunchCore

// Operacions d'edició de la configuració (pures). Els id són fixos: `uuid(n)`.

private func pestanya(_ n: Int, nom: String? = nil) -> Pestanya {
    Pestanya(id: uuid(n), titol: "p\(n)", carpeta: "/Users/prova/p\(n)", claude: ClaudePestanya(nom: nom))
}

/// Dues finestres: «a» amb p11, p12, p13 i p14, i «b» amb p21 i p22.
private func mostra() -> Configuracio {
    Configuracio(finestres: [
        Finestra(id: uuid(1), nom: "a", pestanyes: [pestanya(11, nom: "Botiga"), pestanya(12), pestanya(13), pestanya(14)]),
        Finestra(id: uuid(2), nom: "b", pestanyes: [pestanya(21), pestanya(22)]),
    ])
}

private func titols(_ c: Configuracio) -> [[String]] { c.finestres.map { $0.pestanyes.map(\.titol) } }

@Suite struct EdicioConfiguracioTests {
    @Test func cercar() {
        let c = mostra()
        #expect(c.finestra(uuid(2))?.nom == "b")
        #expect(c.pestanya(uuid(13))?.titol == "p13")
        #expect(c.finestra(dePestanya: uuid(22)) == uuid(2))
        #expect(c.pestanya(uuid(99)) == nil)
        #expect(c.finestra(dePestanya: uuid(99)) == nil)
    }

    @Test func nomsUnics() {
        var c = mostra()
        #expect(c.nomUnic("c") == "c")
        #expect(c.nomUnic("A") == "A 2", "sense distingir majúscules, com la validació")
        c.afegeix(Finestra(id: uuid(3), nom: "a 2"))
        #expect(c.nomUnic("a") == "a 3")
    }

    @Test func finestres() {
        var c = mostra()
        c.afegeix(Finestra(id: uuid(3), nom: "c"), despresDe: uuid(1))
        c.afegeix(Finestra(id: uuid(4), nom: "d"))
        c.afegeix(Finestra(id: uuid(5), nom: "e"), despresDe: uuid(99))
        #expect(c.finestres.map(\.nom) == ["a", "c", "b", "d", "e"])
        #expect(c.eliminaFinestra(uuid(2)) == 2)
        #expect(c.eliminaFinestra(uuid(2)) == nil)
        c.reanomenaFinestra(uuid(1), a: "feina")
        c.reanomenaFinestra(uuid(3), a: "  ")
        #expect(c.finestres.map(\.nom) == ["feina", "c", "d", "e"])
    }

    @Test func duplicarUnaFinestra() throws {
        var c = mostra()
        let ids = IdsDeProva()
        let copia = c.duplicaFinestra(uuid(1), nouId: ids.nou)
        let copia2 = c.duplicaFinestra(uuid(1), nouId: ids.nou)
        #expect(c.finestres.map(\.nom) == ["a", "a còpia 2", "a còpia", "b"])
        #expect(c.finestres[2].id == copia)
        #expect(c.finestres[1].id == copia2)
        let duplicades = c.finestres[2].pestanyes
        #expect(duplicades.map(\.titol) == ["p11", "p12", "p13", "p14"])
        #expect(Set(duplicades.map(\.id)).isDisjoint(with: c.finestres[0].pestanyes.map(\.id)))
        // Sense nom fix de sessió: dues sessions amb el mateix nom es confondrien.
        #expect(duplicades.allSatisfy { $0.claude.nom == nil })
        #expect(c.finestres[0].pestanyes[0].claude.nom == "Botiga")
        #expect(c.duplicaFinestra(uuid(99), nouId: ids.nou) == nil)
    }

    @Test func afegirIEliminarPestanyes() {
        var c = mostra()
        c.afegeix(pestanya(31), a: uuid(2), index: 0)
        c.afegeix(pestanya(32), a: uuid(2))
        c.afegeix(pestanya(33), a: uuid(2), index: 99)
        c.afegeix(pestanya(34), a: uuid(99))
        #expect(titols(c)[1] == ["p31", "p21", "p22", "p32", "p33"])
        c.eliminaPestanyes([uuid(11), uuid(31), uuid(99)])
        #expect(titols(c) == [["p12", "p13", "p14"], ["p21", "p22", "p32", "p33"]])
    }

    @Test func duplicarPestanyes() {
        var c = mostra()
        let noves = c.duplicaPestanyes([uuid(11), uuid(13), uuid(22)], nouId: IdsDeProva().nou)
        #expect(titols(c) == [["p11", "p12", "p13", "p11", "p13", "p14"], ["p21", "p22", "p22"]])
        #expect(noves == [c.finestres[0].pestanyes[3].id, c.finestres[0].pestanyes[4].id, c.finestres[1].pestanyes[2].id])
        #expect(c.finestres[0].pestanyes[3].claude.nom == nil)
        #expect(Set(c.finestres.flatMap(\.pestanyes).map(\.id)).count == 9)
    }

    /// Com `move(fromOffsets:toOffset:)` de SwiftUI: `index` és la posició abans de treure les que es mouen.
    private static let moviments: [(ids: [Int], index: Int, esperat: String)] = [
        ([11], 3, "p12 p13 p11 p14"),
        ([14], 0, "p14 p11 p12 p13"),
        ([11, 13], 4, "p12 p14 p11 p13"),
        ([12, 14], 1, "p11 p12 p14 p13"),
        ([12], 2, "p11 p12 p13 p14"),
        ([12], 1, "p11 p12 p13 p14"),
        ([13, 11], 99, "p12 p14 p11 p13"),
    ]

    @Test func moureDinsDeLaFinestra() {
        for moviment in Self.moviments {
            var c = mostra()
            c.mouPestanyes(Set(moviment.ids.map(uuid)), a: uuid(1), index: moviment.index)
            #expect(titols(c)[0].joined(separator: " ") == moviment.esperat, "\(moviment)")
            #expect(titols(c)[1] == ["p21", "p22"])
        }
    }

    @Test func moureAUnaAltraFinestra() {
        var c = mostra()
        // De dues finestres alhora: en l'ordre en què hi són.
        c.mouPestanyes([uuid(21), uuid(13), uuid(11)], a: uuid(2), index: 1)
        #expect(titols(c) == [["p12", "p14"], ["p11", "p13", "p21", "p22"]])
        c.mouPestanyes([uuid(12)], a: uuid(2))
        #expect(titols(c) == [["p14"], ["p11", "p13", "p21", "p22", "p12"]])
        let abans = c
        c.mouPestanyes([uuid(14)], a: uuid(99))
        c.mouPestanyes([uuid(99)], a: uuid(1))
        #expect(c == abans)
    }

    @Test func canviarPestanyes() {
        var c = mostra()
        c.canviaPestanyes([uuid(12), uuid(21)]) { $0.claude.esforc = "max" }
        #expect(c.finestres.flatMap(\.pestanyes).filter { $0.claude.esforc == "max" }.map(\.titol) == ["p12", "p21"])
    }

    @Test func unaPestanyaNova() {
        let plantilla = ClaudePestanya.habituals
        let nova = Pestanya.nova(id: uuid(1), carpeta: "/Users/prova/GitHub/botiga", plantilla: plantilla, inici: "/Users/prova")
        #expect(nova == Pestanya(id: uuid(1), titol: "botiga", carpeta: "/Users/prova/GitHub/botiga", claude: plantilla))
        // A `~`, sense Claude, com a la importació.
        let aInici = Pestanya.nova(id: uuid(2), carpeta: "/Users/prova", plantilla: plantilla, inici: "/Users/prova")
        #expect(aInici.titol == "Pestanya nova")
        #expect(!aInici.claude.activat)
        #expect(aInici.claude.saltaPermisos, "la resta, de la plantilla, per a «Activa Claude»")
        // Escrita d'una altra manera, també és `~` (com als avisos).
        for carpeta in ["/Users/prova/", "/Users/prova/GitHub/..", "/Users/prova/./"] {
            let nova = Pestanya.nova(id: uuid(3), carpeta: carpeta, plantilla: plantilla, inici: "/Users/prova")
            #expect(!nova.claude.activat, "\(carpeta)")
            #expect(nova.titol == "Pestanya nova", "\(carpeta)")
        }
        #expect(Pestanya.nova(id: uuid(4), carpeta: "/Users/prova/GitHub/botiga/", plantilla: plantilla,
                              inici: "/Users/prova").titol == "botiga")
        #expect(Pestanya.nova(id: uuid(5), carpeta: "/", plantilla: plantilla, inici: "/Users/prova").titol == "Pestanya nova")
        // El nom fix de sessió de la plantilla no es copia (decisió d'en David, 04/11/2026).
        var ambNom = plantilla
        ambNom.nom = "feina"
        let senseNom = Pestanya.nova(id: uuid(6), carpeta: "/Users/prova/GitHub/botiga", plantilla: ambNom, inici: "/Users/prova")
        #expect(senseNom.claude.nom == nil)
        #expect(senseNom.claude == plantilla)
    }
}
