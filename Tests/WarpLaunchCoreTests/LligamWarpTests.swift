import Foundation
import Testing
@testable import WarpLaunchCore

// «Lliga amb Warp…» (0.21.0): la pestanya de Warp de cada pestanya de la configuració sense lligam. Lectures
// inventades; les carpetes no existeixen (la ruta canònica és la mateixa).

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
private let inici = "/Users/prova"
private func pane(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }

private func pestanya(_ n: Int, _ titol: String, _ carpeta: String) -> Pestanya {
    Pestanya(id: id(n), titol: titol, carpeta: carpeta, claude: .habituals)
}

private func configuracio(_ finestres: [[Pestanya]]) -> Configuracio {
    Configuracio(plantilla: .habituals, finestres: finestres.enumerated().map { n, pestanyes in
        Finestra(id: id(100 + n), nom: "F\(n + 1)", pestanyes: pestanyes)
    })
}

private struct DeWarp {
    var titol: String?
    var carpeta: String
    var pane: String
    var claude: SessioClaude? = nil
}

private func claude(_ sessio: String, pane: String, marca: UUID? = nil) -> SessioClaude {
    SessioClaude(pid: 100, sessionId: sessio, carpeta: "/x/c", iniciada: t0, ordre: ["claude"], opcions: OpcionsClaude(),
                 paneUUID: pane, dinsDeWarp: true, marca: marca)
}

private func lectura(_ finestres: [[DeWarp]]) -> LecturaWarp {
    LecturaWarp(finestres: finestres.enumerated().map { n, pestanyes in
        FinestraLlegida(numero: n + 1, pestanyaActiva: 0, pestanyes: pestanyes.enumerated().map { posicio, p in
            PestanyaLlegida(posicio: posicio, titol: p.titol, color: nil, panes: [
                PaneLlegit(uuid: p.pane, carpeta: p.carpeta, origenCarpeta: .pane, carpetaExisteix: true, claude: p.claude),
            ])
        })
    }, sessionsSensePestanya: [], avisos: [])
}

private func proposa(_ c: Configuracio, _ l: LecturaWarp, estat: EstatApp = EstatApp()) -> LligamWarp.Proposta {
    LligamWarp.proposa(c, lectura: l, estat: estat, inici: inici)
}

/// Pestanya de la configuració → (pane, criteri).
private func triades(_ p: LligamWarp.Proposta) -> [UUID: String] {
    Dictionary(uniqueKeysWithValues: p.parelles.map { ($0.id, "\($0.pane.prefix(1)) \($0.criteri)") })
}

@Suite struct LligamWarpTests {
    @Test func pelTitolILaCarpeta() {
        let c = configuracio([[pestanya(1, "A", "/x/a"), pestanya(2, "B", "/x/b")]])
        let l = lectura([
            [DeWarp(titol: "Altra", carpeta: "/x/altra", pane: pane("z"))],
            [DeWarp(titol: "B", carpeta: "/x/b", pane: pane("b")),
             DeWarp(titol: "A", carpeta: "/x/a", pane: pane("a"), claude: claude("s-a", pane: pane("a")))],
        ])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titolICarpeta", id(2): "b titolICarpeta"])
        #expect(p.parelles.map(\.lloc) == ["finestra 2 › A", "finestra 2 › B"])
        #expect(p.senseParella.isEmpty && p.jaLligades == 0 && p.sobrants == 1)
        #expect(p.finestres.map(\.numerosWarp) == [[2]])
        #expect(p.vincles() == [id(1): VincleImportat(pane: pane("a"), sessio: "s-a", carpetaSessio: "/x/c"),
                                id(2): VincleImportat(pane: pane("b"))])
        #expect(p.vincles(excepte: [id(1)]).keys.sorted { $0.uuidString < $1.uuidString } == [id(2)])
    }

    /// Com a `prova2`: en David ha arreglat la carpeta (a Warp, la d'inici o la d'abans), o el títol; i una pestanya
    /// de la configuració amb el títol buit porta el nom de la carpeta. Les majúscules no compten.
    @Test func nomesPelTitolOPerLaCarpeta() {
        let c = configuracio([[pestanya(1, "Pont", "/x/pont"), pestanya(2, "repo", "/x/repo"),
                               pestanya(3, "", "/x/docs"), pestanya(4, "web", "/x/web")]])
        let l = lectura([[
            DeWarp(titol: "Pont", carpeta: inici, pane: pane("a")),
            DeWarp(titol: "Repositori", carpeta: "/x/repo", pane: pane("b")),
            DeWarp(titol: "docs", carpeta: "/x/docs", pane: pane("c")),
            DeWarp(titol: "Web", carpeta: "/x/vella/web", pane: pane("d")),
        ]])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titol", id(2): "b carpeta", id(3): "c titolICarpeta", id(4): "d titol"])
        #expect(p.compta(.titol) == 2 && p.compta(.carpeta) == 1 && p.compta(.titolICarpeta) == 1)
        #expect(!LligamWarp.Criteri.titol.segur && LligamWarp.Criteri.titolICarpeta.segur)
    }

    /// La carpeta sola no lliga a la carpeta d'inici, ni fora de la finestra de Warp que correspon.
    @Test func laCarpetaSolaNomesALaSevaFinestra() {
        let c = configuracio([[pestanya(1, "A", "/x/a"), pestanya(2, "X", "/x/x"), pestanya(3, "Casa", inici)]])
        let l = lectura([
            [DeWarp(titol: "A", carpeta: "/x/a", pane: pane("a")), DeWarp(titol: nil, carpeta: inici, pane: pane("h"))],
            [DeWarp(titol: "Una altra", carpeta: "/x/x", pane: pane("x"))],
        ])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titolICarpeta"])
        #expect(p.senseParella.map(\.id) == [id(2), id(3)])
        #expect(p.sobrants == 2)
    }

    /// Dues pestanyes iguals a la configuració i una a Warp: cap. Dues i dues: per ordre.
    @Test func nomesSiEsInequivoc() {
        let c = configuracio([[pestanya(1, "T", "/x/t"), pestanya(2, "T", "/x/t")]])
        let una = proposa(c, lectura([[DeWarp(titol: "T", carpeta: "/x/t", pane: pane("a"))]]))
        #expect(una.parelles.isEmpty && una.senseParella.count == 2)
        let dues = proposa(c, lectura([[DeWarp(titol: "T", carpeta: "/x/t", pane: pane("a")),
                                        DeWarp(titol: "T", carpeta: "/x/t", pane: pane("b"))]]))
        #expect(triades(dues) == [id(1): "a titolICarpeta", id(2): "b titolICarpeta"])
    }

    /// Les ja lligades (pel pane o per la marca) no es toquen, i la seva pestanya de Warp no és per a cap altra.
    @Test func lesJaLligadesNoEsToquen() {
        let c = configuracio([[pestanya(1, "A", "/x/a"), pestanya(2, "A", "/x/a"), pestanya(3, "M", "/x/m"),
                               pestanya(4, "M", "/x/m")]])
        let l = lectura([[
            DeWarp(titol: "A", carpeta: "/x/a", pane: pane("a")),
            DeWarp(titol: "M", carpeta: "/x/m", pane: pane("m"), claude: claude("s-m", pane: pane("m"), marca: id(3))),
        ]])
        let estat = EstatApp(pestanyes: [id(1): VincleEstat(pane: pane("a"), origen: .importacio, vista: t0)])
        let p = proposa(c, l, estat: estat)
        #expect(p.parelles.isEmpty)
        #expect(p.jaLligades == 2 && p.senseParella.map(\.id) == [id(2), id(4)] && p.sobrants == 0)
        #expect(p.finestres[0].lligades() == 2 && p.finestres[0].numerosWarp == [1])
    }

    /// La conversa que recorda la pestanya, viva en un pane de Warp, mana sobre el títol.
    @Test func laConversaRecordada() {
        let c = configuracio([[pestanya(1, "A", "/x/a")]])
        let l = lectura([[
            DeWarp(titol: "A", carpeta: "/x/a", pane: pane("b")),
            DeWarp(titol: "Un altre", carpeta: "/y", pane: pane("q"), claude: claude("s1", pane: pane("q"))),
        ]])
        let estat = EstatApp(pestanyes: [id(1): VincleEstat(pane: pane("z"), sessio: "s1", origen: .marca, vista: t0)])
        #expect(triades(proposa(c, l, estat: estat)) == [id(1): "q conversa"])
    }

    /// Cada finestra de la configuració, a la seva de Warp; si dues hi empaten, cap, i es busca pel títol a totes.
    @Test func entreFinestres() {
        let c = configuracio([
            [pestanya(1, "A", "/x/a"), pestanya(2, "B", "/x/b"), pestanya(3, "C", "/x/c")],
            [pestanya(4, "D", "/x/d"), pestanya(5, "E", "/x/e")],
        ])
        let l = lectura([
            [DeWarp(titol: "A", carpeta: "/x/a", pane: pane("a")), DeWarp(titol: "Cosa", carpeta: "/x/c", pane: pane("c"))],
            [DeWarp(titol: "B", carpeta: "/x/b", pane: pane("b"))],
            [DeWarp(titol: "D", carpeta: "/x/d", pane: pane("d"))],
            [DeWarp(titol: "E", carpeta: "/x/e", pane: pane("e"))],
        ])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titolICarpeta", id(2): "b titolICarpeta", id(3): "c carpeta",
                               id(4): "d titolICarpeta", id(5): "e titolICarpeta"])
        #expect(p.finestres.map(\.numerosWarp) == [[1, 2], [3, 4]])
    }

    /// Un criteri feble a la finestra no pren la pestanya de Warp que coincideix del tot amb una altra finestra de la
    /// configuració (revisió de la 0.21.0): «Comú» s'ha mogut a la finestra 1 de Warp, i «Notes» ja no hi és.
    @Test func unCriteriFebleNoPrenLaDUnaAltraFinestra() {
        let c = configuracio([
            [pestanya(1, "Alfa", "/r/alfa"), pestanya(2, "Notes", "/r/comu")],
            [pestanya(3, "Comú", "/r/comu"), pestanya(4, "Beta", "/r/beta"), pestanya(5, "Gamma", "/r/gamma")],
        ])
        let l = lectura([
            [DeWarp(titol: "Alfa", carpeta: "/r/alfa", pane: pane("a")), DeWarp(titol: "Comú", carpeta: "/r/comu", pane: pane("c"))],
            [DeWarp(titol: "Beta", carpeta: "/r/beta", pane: pane("b")), DeWarp(titol: "Gamma", carpeta: "/r/gamma", pane: pane("g"))],
        ])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titolICarpeta", id(3): "c titolICarpeta", id(4): "b titolICarpeta",
                               id(5): "g titolICarpeta"])
        #expect(p.senseParella.map(\.id) == [id(2)])
    }

    /// Dues finestres de la configuració amb una pestanya a la mateixa carpeta, i a Warp només una (sense el títol de
    /// cap): no se sap de quina és.
    @Test func laCarpetaSolaAmbDuesFinestres() {
        let c = configuracio([
            [pestanya(1, "A", "/x/a"), pestanya(2, "Notes", "/r/comu")],
            [pestanya(3, "B", "/x/b"), pestanya(4, "Comú", "/r/comu")],
        ])
        let l = lectura([
            [DeWarp(titol: "A", carpeta: "/x/a", pane: pane("a")), DeWarp(titol: "Altres", carpeta: "/r/comu", pane: pane("c"))],
            [DeWarp(titol: "B", carpeta: "/x/b", pane: pane("b"))],
        ])
        let p = proposa(c, l)
        #expect(triades(p) == [id(1): "a titolICarpeta", id(3): "b titolICarpeta"])
        #expect(p.senseParella.map(\.id) == [id(2), id(4)])
    }

    /// Una pestanya de Warp sense títol, amb el pane a la carpeta d'inici i el Claude a la de la pestanya: com a la
    /// importació, el títol és el nom de la carpeta del Claude.
    @Test func comLaImportacio() {
        let c = configuracio([[pestanya(1, "repo", "/r/repo"), pestanya(2, "", "/r/docs")]])
        let l = lectura([[
            DeWarp(titol: nil, carpeta: inici, pane: pane("a"), claude: claude("s-r", pane: pane("a"))),
            DeWarp(titol: nil, carpeta: "/r/docs", pane: pane("d")),
        ]])
        var conClaude = l
        conClaude.finestres[0].pestanyes[0].panes[0].claude?.carpeta = "/r/repo"
        let p = proposa(c, conClaude)
        #expect(triades(p) == [id(1): "a titolICarpeta", id(2): "d titolICarpeta"])
        #expect(p.parelles[0].claude?.sessionId == "s-r")
    }

    /// La conversa recordada en el segon pane d'una pestanya dividida: es lliga aquell pane, amb el seu Claude.
    @Test func laConversaEnUnaPestanyaDividida() {
        let c = configuracio([[pestanya(1, "A", "/x/a")]])
        let estat = EstatApp(pestanyes: [id(1): VincleEstat(pane: pane("z"), sessio: "s2", origen: .pane, vista: t0)])
        let l = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Dividida", color: nil, panes: [
                PaneLlegit(uuid: pane("p"), carpeta: "/y", origenCarpeta: .pane, carpetaExisteix: true,
                           claude: claude("s1", pane: pane("p"))),
                PaneLlegit(uuid: pane("q"), carpeta: "/y", origenCarpeta: .pane, carpetaExisteix: true,
                           claude: claude("s2", pane: pane("q"))),
            ]),
        ])], sessionsSensePestanya: [], avisos: [])
        let p = proposa(c, l, estat: estat)
        #expect(triades(p) == [id(1): "q conversa"])
        #expect(p.vincles()[id(1)]?.sessio == "s2")
    }

    @Test func lligaConservaLaConversa() {
        let estat = EstatApp(pestanyes: [
            id(1): VincleEstat(pane: pane("z"), sessio: "s1", carpetaSessio: "/x/1", origen: .marca, vista: t0),
            id(2): VincleEstat(pane: pane("a"), sessio: "s2", carpetaSessio: "/x/2", origen: .pane, vista: t0),
            id(4): VincleEstat(pane: pane("b"), sessio: "s4", carpetaSessio: "/x/4", origen: .pane, vista: t0,
                               foraDesDe: t0),
        ])
        let ara = t0 + 60.4
        let nou = ActualitzaEstat.lliga([
            id(1): VincleImportat(pane: pane("a")),
            id(3): VincleImportat(pane: pane("b")),
            id(5): VincleImportat(pane: pane("c"), sessio: "s5", carpetaSessio: "/x/5"),
        ], estat: estat, ara: ara)
        let segon = t0 + 60
        #expect(nou.pestanyes[id(1)] == VincleEstat(pane: pane("a"), sessio: "s1", carpetaSessio: "/x/1",
                                                     origen: .importacio, vista: segon))
        // El pane és d'una sola pestanya: T2 el perd, però no la conversa.
        #expect(nou.pestanyes[id(2)] == VincleEstat(pane: nil, sessio: "s2", carpetaSessio: "/x/2", origen: .pane,
                                                     vista: segon))
        // Sense conversa pròpia, hereta la de l'entrada que tenia el pane.
        #expect(nou.pestanyes[id(3)]?.sessio == "s4" && nou.pestanyes[id(4)]?.pane == nil)
        #expect(nou.pestanyes[id(5)]?.sessio == "s5" && nou.pestanyes[id(5)]?.carpetaSessio == "/x/5")
    }
}
