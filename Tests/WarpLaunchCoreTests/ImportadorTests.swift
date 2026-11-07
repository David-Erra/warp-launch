import Foundation
import Testing
@testable import WarpLaunchCore

// Importació (docs/disseny.md, «Importació (R2)»). Lectures fictícies: l'importador no toca el disc.

private let inici = "/Users/prova"
private let habitual = "claude --dangerously-skip-permissions --effort ultracode --continue"

/// Fabrica lectures fictícies amb pids i UUID de pane únics.
private struct Fabrica {
    private var n: Int32 = 0

    mutating func sessio(_ carpeta: String, _ argv: [String], nom: String? = nil) -> SessioClaude {
        n += 1
        return SessioClaude(pid: 1000 + n, sessionId: "s-\(n)", nom: nom, origenNom: nom == nil ? nil : "derived",
                            carpeta: carpeta, estat: "idle", iniciada: nil, ordre: argv,
                            opcions: OpcionsClaude.analitza(argv), paneUUID: nil, dinsDeWarp: true)
    }

    mutating func pane(_ carpeta: String, existeix: Bool = true, claude: SessioClaude? = nil) -> PaneLlegit {
        n += 1
        return PaneLlegit(uuid: String(format: "%032x", n), carpeta: carpeta, origenCarpeta: .pane,
                          carpetaExisteix: existeix, claude: claude)
    }

    /// Una pestanya a partir d'un codi: `~` (carpeta d'inici), `x:ruta` (no existeix), `p:ruta` (sense Claude),
    /// `c:ruta` (Claude amb `--continue`), `n:ruta` (Claude sense `--continue`). Les rutes són relatives a l'inici.
    mutating func pestanya(_ codi: String, titol: String? = "Títol") -> PestanyaLlegida {
        let parts = codi.split(separator: ":", maxSplits: 1).map(String.init)
        let carpeta = parts.count == 2 ? "\(inici)/\(parts[1])" : inici
        let p: PaneLlegit
        switch parts[0] {
        case "~": p = pane(inici)
        case "x": p = pane(carpeta, existeix: false)
        case "p": p = pane(carpeta)
        case "c": p = pane(carpeta, claude: sessio(carpeta, ["claude", "--dangerously-skip-permissions", "--continue", "--effort", "ultracode"]))
        case "n": p = pane(carpeta, claude: sessio(carpeta, ["claude", "--dangerously-skip-permissions", "--effort", "ultracode"]))
        default: fatalError("codi desconegut \(codi)")
        }
        return PestanyaLlegida(posicio: 0, titol: titol, color: nil, panes: [p])
    }

    mutating func lectura(_ finestres: [[String]], sensePestanya: [SessioClaude] = []) -> LecturaWarp {
        LecturaWarp(
            finestres: finestres.enumerated().map { f, codis in
                FinestraLlegida(numero: f + 1, pestanyaActiva: 0,
                                pestanyes: codis.enumerated().map { p, codi in
                                    var pestanya = pestanya(codi)
                                    pestanya.posicio = p
                                    return pestanya
                                })
            },
            sessionsSensePestanya: sensePestanya, avisos: [])
    }
}

private func repeteix(_ codi: String, _ vegades: Int) -> [String] {
    (1...vegades).map { codi.replacingOccurrences(of: "#", with: "\($0)") }
}

/// Una lectura gran, inventada: 7 finestres (21, 17, 1, 2, 6, 9 i 4 pestanyes), 13 sessions (10 amb `--continue`),
/// 11 pestanyes a `~` i 5 amb una carpeta que ja no existeix.
private func lecturaGran() -> LecturaWarp {
    var fabrica = Fabrica()
    return fabrica.lectura([
        ["~"] + repeteix("p:GitHub/feina/eina-#", 6) + repeteix("x:documents/codi/feina/web-#", 5)
            + repeteix("p:GitHub/feina/cli-#", 3) + ["~"] + repeteix("p:GitHub/feina/agent-#", 5),
        ["c:GitHub/feina/estudi", "~", "p:GitHub/feina/moduls"] + repeteix("~", 4)
            + repeteix("p:GitHub/feina/estudi-agent-#", 2) + ["~"] + repeteix("p:GitHub/feina/oficina-#", 3)
            + repeteix("~", 2) + ["p:GitHub/feina", "p:GitHub/feina/connector-mcp"],
        ["~"],
        ["c:GitHub/casa/notes", "c:GitHub/casa/diagrames"],
        ["c:Codi/agenda", "c:GitHub/feina/xat", "n:GitHub/casa/warp-launch",
         "c:GitHub/feina/biblioteca", "c:GitHub/taller/taller-eines", "c:GitHub/feina/finances"],
        repeteix("p:GitHub/taller/taller-#", 9),
        ["n:Codi/proj-1", "n:Codi/proj-2", "c:Codi/proj-3", "c:Codi/calculadora"],
    ])
}

@Suite struct ImportadorTests {
    /// Fase 3.1: cada pestanya importada recorda el seu pane (totes, també les de terminal) i, si hi corria Claude, la
    /// seva conversa i la carpeta de la sessió.
    @Test func lesPestanyesImportadesRecordenElPaneILaConversa() throws {
        let lectura = lecturaGran()
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanyes = importacio.configuracio.finestres.flatMap(\.pestanyes)
        #expect(importacio.vincles.count == 60)
        #expect(Set(importacio.vincles.keys) == Set(pestanyes.map(\.id)))
        #expect(importacio.vincles.values.filter { $0.sessio != nil }.count == 13)
        // En el mateix ordre que la lectura: el pane i la sessió de cada pestanya.
        let panes = lectura.finestres.flatMap(\.pestanyes).compactMap(\.panes.first)
        for (pestanya, pane) in zip(pestanyes, panes) {
            #expect(importacio.vincles[pestanya.id]
                == VincleImportat(pane: pane.uuid, sessio: pane.claude?.sessionId, carpetaSessio: pane.claude?.carpeta))
        }
    }

    @Test func unaLecturaGranDona44AmbClaudeI16Sense() throws {
        let importacio = Importador.importa(lecturaGran(), inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.resum == ResumImportacio(finestres: 7, pestanyes: 60, ambSessio: 13, ambPlantilla: 31,
                                                    senseClaude: 16, senseClaudeObert: 0, saltenPermisos: 44))
        #expect(importacio.resum.descripcio
            == "7 finestres · 60 pestanyes · 44 amb Claude (13 amb la seva ordre, 31 amb la plantilla) · 16 només terminal")
        let c = importacio.configuracio
        #expect(c.finestres.map(\.pestanyes.count) == [21, 17, 1, 2, 6, 9, 4])
        #expect(c.finestres.map(\.nom)
            == ["feina", "feina 2", "Finestra 3", "casa", "Finestra 5", "taller", "Codi"])
        #expect(c.plantilla == .habituals)
        #expect(importacio.notes.isEmpty)
        // Per què n'hi ha 16 sense Claude (el full d'importació ho diu).
        #expect(importacio.compta(.carpetaInici) == 11)
        #expect(importacio.compta(.carpetaNoExisteix) == 5)
        #expect(importacio.compta(.sessio) == 13)

        // Totes les pestanyes amb Claude, amb la comanda de `.habituals`; les 16 sense, amb la plantilla apagada.
        let pestanyes = c.finestres.flatMap(\.pestanyes)
        for pestanya in pestanyes where pestanya.claude.activat {
            // Continua: amb la conversa de la pestanya, `--resume` on la comanda tenia `--continue` (D7).
            #expect(OrdreClaude.text(try #require(try OrdreClaude.argv(pestanya.claude, repren: "id-1")))
                == habitual.replacingOccurrences(of: "--continue", with: "--resume id-1"))
        }
        var apagada = ClaudePestanya.habituals
        apagada.activat = false
        #expect(pestanyes.filter { !$0.claude.activat }.allSatisfy { $0.claude == apagada })

        // Id únics: 60 pestanyes i 7 finestres.
        #expect(Set(pestanyes.map(\.id) + c.finestres.map(\.id)).count == 67)
    }

    /// En una configuració nova, les pestanyes on no corria Claude queden només terminal (D-P5a, en David, 07/11/2026).
    /// Les que tenien Claude conserven la seva ordre, i les de `~` i les d'una carpeta que no existeix, com sempre.
    @Test func unaConfiguracioNovaDeixaNomesTerminalLesQueNoTenienClaude() throws {
        let importacio = Importador.importa(lecturaGran(), inici: inici, plantilla: .perOmissio,
                                            senseSessio: .nomesTerminal, nouId: IdsDeProva().nou)
        #expect(importacio.resum == ResumImportacio(finestres: 7, pestanyes: 60, ambSessio: 13, ambPlantilla: 0,
                                                    senseClaude: 47, senseClaudeObert: 31, saltenPermisos: 13))
        #expect(importacio.resum.descripcio
            == "7 finestres · 60 pestanyes · 13 amb Claude, amb la seva ordre · 47 només terminal (31 sense Claude obert)")
        #expect(importacio.compta(.nomesTerminal) == 31)
        #expect(importacio.compta(.plantilla) == 0)
        #expect(importacio.compta(.carpetaInici) == 11)
        #expect(importacio.compta(.carpetaNoExisteix) == 5)
        #expect(importacio.compta(.sessio) == 13)
        #expect(importacio.configuracio.plantilla == .perOmissio)

        let pestanyes = importacio.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyes.filter { !$0.claude.activat }.allSatisfy { $0.claude == .nomesTerminal })
        for pestanya in pestanyes where pestanya.claude.activat {
            #expect(importacio.origens[pestanya.id] == .sessio)
            #expect(OrdreClaude.text(try #require(try OrdreClaude.argv(pestanya.claude, repren: "id-1")))
                == habitual.replacingOccurrences(of: "--continue", with: "--resume id-1"))
        }
        // Totes recorden el seu pane, també les que queden només terminal (fase 3.1).
        #expect(importacio.vincles.count == 60)
    }

    /// Tornar a importar sobre una configuració que ja existeix no canvia: on no corria Claude, la plantilla (D11). Fora
    /// d'aquestes pestanyes, les dues importacions són iguals; i, en una configuració nova, si s'hi activa Claude, ja té
    /// les opcions de la plantilla.
    @Test func tornarAImportarDonaLaPlantillaOnNoCorriaClaude() throws {
        let nova = Importador.importa(lecturaGran(), inici: inici, plantilla: .habituals,
                                      senseSessio: .nomesTerminal, nouId: IdsDeProva().nou)
        let tornada = Importador.importa(lecturaGran(), inici: inici, plantilla: .habituals,
                                         senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(tornada.resum.ambPlantilla == 31 && tornada.resum.senseClaudeObert == 0)
        #expect(nova.resum.ambPlantilla == 0 && nova.resum.senseClaudeObert == 31)

        var apagada = ClaudePestanya.habituals
        apagada.activat = false
        let pestanyesNova = nova.configuracio.finestres.flatMap(\.pestanyes)
        let pestanyesTornada = tornada.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyesNova.map(\.id) == pestanyesTornada.map(\.id))
        for (n, t) in zip(pestanyesNova, pestanyesTornada) {
            #expect(n.titol == t.titol && n.carpeta == t.carpeta)
            if tornada.origens[t.id] == .plantilla {
                #expect(t.claude == .habituals)
                #expect(nova.origens[n.id] == .nomesTerminal)
                #expect(n.claude == apagada)
            } else {
                #expect(n == t)
                #expect(nova.origens[n.id] == tornada.origens[t.id])
            }
        }
        #expect(nova.configuracio.finestres.map(\.nom) == tornada.configuracio.finestres.map(\.nom))
        #expect(nova.vincles == tornada.vincles)
        #expect(nova.notes == tornada.notes)
    }

    /// Amb Warp tancat (la foto, sense cap sessió viva), cap pestanya conserva la seva ordre: en una configuració nova
    /// queden totes només terminal (D-P5a), i en tornar a importar prenen la plantilla (D11). L'avís de la foto ho diu
    /// sense prometre la plantilla, que en una configuració nova no hi és (revisió de la 0.29.1).
    @Test func ambWarpTancatCapPestanyaConservaLaSevaOrdre() throws {
        var f = Fabrica()
        let lectura = f.lectura([["p:GitHub/a", "p:GitHub/b", "~"]])
        let nova = Importador.importa(lectura, inici: inici, plantilla: .perOmissio, senseSessio: .nomesTerminal,
                                      nouId: IdsDeProva().nou)
        #expect(nova.resum.ambSessio == 0 && nova.resum.ambPlantilla == 0)
        #expect(nova.configuracio.finestres.flatMap(\.pestanyes).allSatisfy { !$0.claude.activat })
        let tornada = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla,
                                         nouId: IdsDeProva().nou)
        #expect(tornada.resum.ambSessio == 0 && tornada.resum.ambPlantilla == 2)

        #expect(LecturaWarp.avisFotoWarpTancat.contains("cap pestanya conserva la seva ordre"))
        #expect(!LecturaWarp.avisFotoWarpTancat.contains("plantilla"))
    }

    @Test func esDesaIEsTornaALlegirIgual() throws {
        let configuracio = Importador.importa(lecturaGran(), inici: inici, plantilla: .habituals, senseSessio: .plantilla,
                                              nouId: IdsDeProva().nou).configuracio
        let llegida = try Configuracio.llegeix(try configuracio.json(), inici: inici)
        #expect(llegida.configuracio == configuracio)
        #expect(llegida.avisos.isEmpty)
    }

    @Test func elsAvisosDUnaLecturaGran() throws {
        let configuracio = Importador.importa(lecturaGran(), inici: inici, plantilla: .habituals, senseSessio: .plantilla,
                                              nouId: IdsDeProva().nou).configuracio
        let avisos = Validacio.avisos(configuracio, inici: inici) { !$0.contains("/documents/") }
        #expect(avisos.compta(.error) == 0)
        #expect(avisos.compta(.avis) == 16)
        #expect(avisos.tots.filter { $0.tipus == .carpetaInici }.count == 11)
        #expect(avisos.tots.filter { $0.tipus == .carpetaNoExisteix }.count == 5)
        #expect(avisos.tots.filter { $0.tipus == .ultracode }.count == 44)
    }

    @Test func unaSessioVivaConservaLaSevaOrdreIContinua() throws {
        var f = Fabrica()
        let argv = ["claude", "--model", "opus", "-n", "Botiga", "--permission-mode", "plan", "--add-dir", "/a", "/b"]
        let sessio = f.sessio("\(inici)/botiga", argv, nom: "nom-de-claude")
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", color: nil, panes: [f.pane("\(inici)/botiga", claude: sessio)]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanya = try #require(importacio.configuracio.finestres.first?.pestanyes.first)
        // Les opcions de la sessió, no les de la plantilla; continua (R4); el nom només el de `-n`.
        #expect(pestanya.claude == ClaudePestanya(model: "opus", continua: true, nom: "Botiga", modePermisos: "plan",
                                                  altres: ["--add-dir", "/a", "/b"]))
        #expect(importacio.origens[pestanya.id] == .sessio)
        #expect(importacio.resum.saltenPermisos == 0)
    }

    @Test func senseSessioLaPlantillaICapSaltDePermisosPerOmissio() throws {
        var f = Fabrica()
        let lectura = f.lectura([["p:GitHub/a", "~", "x:GitHub/perduda"]])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .perOmissio, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanyes = importacio.configuracio.finestres[0].pestanyes
        #expect(pestanyes.map(\.claude) == [.perOmissio, .nomesTerminal, .nomesTerminal])
        #expect(pestanyes.allSatisfy { !$0.claude.saltaPermisos })
        #expect(pestanyes.map { importacio.origens[$0.id] } == [.plantilla, .carpetaInici, .carpetaNoExisteix])

        // En una configuració nova, la primera també queda només terminal (D-P5a); les altres dues, pel mateix motiu.
        let nova = Importador.importa(lectura, inici: inici, plantilla: .perOmissio, senseSessio: .nomesTerminal,
                                      nouId: IdsDeProva().nou)
        let pestanyesNova = nova.configuracio.finestres[0].pestanyes
        #expect(pestanyesNova.map(\.claude) == [.nomesTerminal, .nomesTerminal, .nomesTerminal])
        #expect(pestanyesNova.map { nova.origens[$0.id] } == [.nomesTerminal, .carpetaInici, .carpetaNoExisteix])
        #expect(nova.resum.descripcio == "1 finestra · 3 pestanyes · 0 amb Claude · 3 només terminal (1 sense Claude obert)")
    }

    @Test func elsNomsDeFinestra() {
        func nom(_ carpetes: [String]) -> String? {
            Importador.nomDeFinestra(carpetes.map { $0 == "~" ? inici : "\(inici)/\($0)" }, inici: inici)
        }
        #expect(nom(["GitHub/empresa/a", "GitHub/empresa/b", "GitHub/altres/c"]) == "empresa")
        #expect(nom(["GitHub/empresa/a", "GitHub/altres/c"]) == nil, "la meitat no n'és més de la meitat")
        #expect(nom(["~", "~", "~", "GitHub/empresa/a"]) == "empresa", "les de ~ no compten")
        #expect(nom(["~", "~"]) == nil)
        #expect(nom([]) == nil)
        #expect(nom(["projecte-a", "projecte-b"]) == nil, "la carpeta d'inici no és cap nom")
        #expect(Importador.nomDeFinestra(["/a", "/b"], inici: inici) == nil, "l'arrel tampoc")
    }

    @Test func elsNomsRepetitsPortenUnNumero() {
        var f = Fabrica()
        let lectura = f.lectura([["p:GitHub/Empresa/a"], ["p:GitHub/empresa/b"], ["~"], ["p:GitHub/empresa/c"],
                                 ["p:Finestra 3/d"]])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.configuracio.finestres.map(\.nom)
            == ["Empresa", "empresa 2", "Finestra 3", "empresa 3", "Finestra 3 2"])
        let avisos = Validacio.avisos(importacio.configuracio, inici: inici) { _ in true }
        #expect(avisos.finestres.isEmpty)
    }

    @Test func elTitolDeLaPestanya() {
        #expect(Importador.titol("Botiga", carpeta: "\(inici)/botiga", inici: inici, numero: 1) == "Botiga")
        #expect(Importador.titol(nil, carpeta: "\(inici)/GitHub/warp-launch", inici: inici, numero: 1) == "warp-launch")
        #expect(Importador.titol("  ", carpeta: "\(inici)/GitHub/warp-launch", inici: inici, numero: 1) == "warp-launch")
        #expect(Importador.titol(nil, carpeta: inici, inici: inici, numero: 4) == "Pestanya 4")
        #expect(Importador.titol("", carpeta: "/", inici: inici, numero: 2) == "Pestanya 2")
    }

    @Test func elPanePrincipalEsElPrimerAmbClaude() throws {
        var f = Fabrica()
        let sessio = f.sessio("\(inici)/b", ["claude", "-c"])
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Dividida", color: nil,
                            panes: [f.pane("\(inici)/a"), f.pane("\(inici)/b", claude: sessio)]),
            PestanyaLlegida(posicio: 1, titol: "Dues sessions", color: nil,
                            panes: [f.pane("\(inici)/c", claude: f.sessio("\(inici)/c", ["claude"])),
                                    f.pane("\(inici)/d", claude: f.sessio("\(inici)/d", ["claude"]))]),
            PestanyaLlegida(posicio: 2, titol: "Sense Claude", color: nil, panes: [f.pane("\(inici)/e"), f.pane("\(inici)/f")]),
            PestanyaLlegida(posicio: 3, titol: "Sense panes", color: nil, panes: []),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanyes = importacio.configuracio.finestres[0].pestanyes
        #expect(pestanyes.map(\.carpeta) == ["\(inici)/b", "\(inici)/c", "\(inici)/e"])
        #expect(importacio.notes.map(\.description) == [
            "Finestra 1 › Dividida: pestanya dividida en 2 panes; només s'importa el principal",
            "Finestra 1 › Dues sessions: pestanya dividida en 2 panes; només s'importa el principal, i es perd 1 sessió de Claude",
            "Finestra 1 › Sense Claude: pestanya dividida en 2 panes; només s'importa el principal",
        ])
        #expect(importacio.notes.compactMap(\.lloc?.pestanya) == pestanyes.map(\.id))
    }

    @Test func unaSessioEnUnaPestanyaALIniciPortaLaSevaCarpeta() throws {
        var f = Fabrica()
        let sessio = f.sessio("\(inici)/GitHub/botiga", ["claude", "-c"])
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", color: nil, panes: [f.pane(inici, claude: sessio)]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanya = importacio.configuracio.finestres[0].pestanyes[0]
        #expect(pestanya.carpeta == "\(inici)/GitHub/botiga")
        #expect(pestanya.claude.activat)
        #expect(importacio.configuracio.finestres[0].nom == "GitHub")
        #expect(importacio.notes == [.carpetaDeLaSessio(Lloc(pestanya: pestanya.id, text: "GitHub › Botiga"),
                                                        pestanya: inici, sessio: "\(inici)/GitHub/botiga")])
    }

    @Test func unaFinestraSensePestanyesDeTerminalNoSImporta() {
        var f = Fabrica()
        var lectura = f.lectura([["p:GitHub/a/x"], [], ["p:GitHub/b/y"]])
        lectura.finestres[1].pestanyes = [PestanyaLlegida(posicio: 0, titol: "Buida", color: nil, panes: [])]
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.configuracio.finestres.map(\.nom) == ["a", "b"])
        #expect(importacio.notes.map(\.description) == ["la finestra 2 de Warp no té cap pestanya de terminal: no s'importa"])
    }

    @Test func siLaPestanyaNoEsALIniciManaLaSevaCarpeta() throws {
        var f = Fabrica()
        // El `cwd` de la sessió potser segueix els `cd` de Claude: es queda la de la pestanya, i es diu.
        let sessio = f.sessio("\(inici)/GitHub/botiga/src", ["claude", "-c"])
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", color: nil, panes: [f.pane("\(inici)/GitHub/botiga", claude: sessio)]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanya = importacio.configuracio.finestres[0].pestanyes[0]
        #expect(pestanya.carpeta == "\(inici)/GitHub/botiga")
        #expect(importacio.notes.map(\.description) == [
            "GitHub › Botiga: Warp diu «/Users/prova/GitHub/botiga» i Claude «/Users/prova/GitHub/botiga/src»; es fa servir la de Warp (comprova-ho)",
        ])
        #expect(importacio.notes.first?.lloc?.pestanya == pestanya.id)
    }

    @Test func elPrimerMissatgeNoEsDesaPeroEsDiu() throws {
        var f = Fabrica()
        let sessio = f.sessio("\(inici)/a", ["claude", "--dangerously-skip-permissions", "-c", "revisa el pas 6"])
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "A", color: nil, panes: [f.pane("\(inici)/a", claude: sessio)]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let pestanya = importacio.configuracio.finestres[0].pestanyes[0]
        #expect(try OrdreClaude.argv(pestanya.claude, repren: nil) == ["claude", "--dangerously-skip-permissions"])
        #expect(pestanya.claude.continua)
        #expect(importacio.notes.map(\.description) == [
            "Finestra 1 › A: la sessió es va obrir amb el missatge «revisa el pas 6»; no es desa (s'enviaria a cada obertura)",
        ])
    }

    @Test func unMissatgeLlargEsRetalla() {
        let lloc = Lloc(pestanya: uuid(1), text: "f › p")
        let nota = NotaImportacio.primerMissatgeDescartat(lloc, missatge: String(repeating: "a", count: 100))
        #expect(nota.description.contains("«" + String(repeating: "a", count: 59) + "…»"))
    }

    @Test func unaConversaConcretaEsDesaComContinuar() throws {
        var f = Fabrica()
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "R", color: nil,
                            panes: [f.pane("\(inici)/a", claude: f.sessio("\(inici)/a", ["claude", "-r", "abc"]))]),
            PestanyaLlegida(posicio: 1, titol: "S", color: nil,
                            panes: [f.pane("\(inici)/b", claude: f.sessio("\(inici)/b", ["claude", "--session-id", "u-1"]))]),
            PestanyaLlegida(posicio: 2, titol: "T", color: nil,
                            panes: [f.pane("\(inici)/c", claude: f.sessio("\(inici)/c", ["claude", "-r"]))]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.configuracio.finestres[0].pestanyes.map(\.claude) == Array(repeating: .perOmissio, count: 3))
        #expect(importacio.notes.map(\.description) == [
            "Finestra 1 › R: la sessió es va obrir amb «--resume» (una conversa concreta); es desa només que continua",
            "Finestra 1 › S: la sessió es va obrir amb «--session-id» (una conversa concreta); es desa només que continua",
        ])
    }

    @Test func lesSessionsSensePestanyaNoSImporten() {
        var f = Fabrica()
        var fora = f.sessio("\(inici)/a", ["claude"], nom: "fora")
        fora.dinsDeWarp = false
        let perduda = f.sessio("\(inici)/b", ["claude"])
        let lectura = f.lectura([["p:GitHub/a", "p:a"]], sensePestanya: [fora, perduda])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.resum.pestanyes == 2)
        // La pestanya de la mateixa carpeta s'ha importat amb la plantilla, no amb les opcions de la sessió: es diu.
        #expect(importacio.notes.map(\.description) == [
            "sessió de Claude «fora» a «/Users/prova/a»: no s'importa (corre fora de Warp, o dins de tmux); a la mateixa "
                + "carpeta hi ha «Finestra 1 › Títol», que no porta les seves opcions",
            "sessió de Claude a «/Users/prova/b»: no s'importa (la seva pestanya no és a la base de Warp)",
        ])

        // En una configuració nova, la pestanya de la mateixa carpeta no obre Claude: la nota no diu que només li
        // falten les opcions (D-P5a, revisió de la 0.29.1).
        let nova = Importador.importa(lectura, inici: inici, plantilla: .perOmissio, senseSessio: .nomesTerminal,
                                      nouId: IdsDeProva().nou)
        #expect(nova.notes.map(\.description).first == "sessió de Claude «fora» a «/Users/prova/a»: no s'importa "
            + "(corre fora de Warp, o dins de tmux); a la mateixa carpeta hi ha «Finestra 1 › Títol», que queda només terminal")
    }

    /// Una sessió sense pestanya a una carpeta amb pestanyes de cada mena: les que obren Claude amb la plantilla i les
    /// que queden només terminal (a `~`) es diuen per separat, en plural si n'hi ha més d'una.
    @Test func laNotaDUnaSessioSensePestanyaSeparaLesQueQuedenNomesTerminal() {
        var f = Fabrica()
        let aInici = f.sessio(inici, ["claude"])
        let aDues = f.sessio("\(inici)/a", ["claude"])
        let barrejades = f.sessio("\(inici)/c", ["claude"])
        let lectura = f.lectura([["~", "~", "p:a", "p:a", "p:c", "x:c"]], sensePestanya: [aInici, aDues, barrejades])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: .habituals, senseSessio: .plantilla,
                                            nouId: IdsDeProva().nou)
        #expect(importacio.notes.map(\.description) == [
            "sessió de Claude a «/Users/prova»: no s'importa (la seva pestanya no és a la base de Warp); a la mateixa "
                + "carpeta hi ha «Finestra 1 › Títol», «Finestra 1 › Títol», que queden només terminal",
            "sessió de Claude a «/Users/prova/a»: no s'importa (la seva pestanya no és a la base de Warp); a la mateixa "
                + "carpeta hi ha «Finestra 1 › Títol», «Finestra 1 › Títol», que no porten les seves opcions",
            "sessió de Claude a «/Users/prova/c»: no s'importa (la seva pestanya no és a la base de Warp); a la mateixa "
                + "carpeta hi ha «Finestra 1 › Títol», que no porta les seves opcions; i «Finestra 1 › Títol», que queda "
                + "només terminal",
        ])
    }

    @Test func laPlantillaEsCopiaANormalitzada() {
        var f = Fabrica()
        let plantilla = ClaudePestanya(model: "  ", esforc: " ULTRACODE ")
        let importacio = Importador.importa(f.lectura([["p:a"]]), inici: inici, plantilla: plantilla, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        let esperada = ClaudePestanya(esforc: "xhigh", ultracode: true)
        #expect(importacio.configuracio.plantilla == esperada)
        #expect(importacio.configuracio.finestres[0].pestanyes[0].claude == esperada)
    }

    /// Un nom fix de sessió a la plantilla (escrit a mà al fitxer) no passa a cap pestanya importada: totes s'obririen
    /// amb el mateix nom (decisió d'en David, 04/11/2026). La plantilla de la configuració el conserva.
    @Test func elNomDeSessioDeLaPlantillaNoEsCopia() {
        var f = Fabrica()
        var plantilla = ClaudePestanya.habituals
        plantilla.nom = "feina"
        let lectura = f.lectura([["p:a", "p:b"]])
        let importacio = Importador.importa(lectura, inici: inici, plantilla: plantilla, senseSessio: .plantilla, nouId: IdsDeProva().nou)
        #expect(importacio.configuracio.plantilla.nom == "feina")
        let pestanyes = importacio.configuracio.finestres.flatMap(\.pestanyes)
        #expect(!pestanyes.isEmpty)
        #expect(pestanyes.allSatisfy { $0.claude.nom == nil })
    }
}
