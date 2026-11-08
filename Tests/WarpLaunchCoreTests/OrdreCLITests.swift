import Foundation
import Testing
@testable import WarpLaunchCore

// La comanda `warp-launch` (OrdreCLI), amb una base de Warp de prova i sessions falses. La «configuració real»
// també és una carpeta temporal.

private struct Escenari {
    let tmp: CarpetaTemporal
    let inici: String
    let real: URL
    let entorn: EntornCLI

    /// Warp amb dues finestres: «A» amb Claude, «B» sense, i una pestanya a la carpeta d'inici.
    init(argv: [String] = ["claude", "--dangerously-skip-permissions", "--continue", "--effort", "ultracode"]) throws {
        tmp = try CarpetaTemporal()
        inici = try tmp.carpeta("inici")
        let a = try tmp.carpeta("inici/GitHub/projectes/a")
        let b = try tmp.carpeta("inici/GitHub/projectes/b")
        real = tmp.url("inici/config-real")

        let base = try BaseWarpDeProva(a: tmp.url("warp.sqlite"))
        try base.finestra(1)
        try base.finestra(2)
        try base.pestanya(1, finestra: 1, titol: "A")
        try base.pestanya(2, finestra: 1, titol: "B")
        try base.pestanya(3, finestra: 2)
        try base.paneTerminal(10, pestanya: 1, uuid: uuidDeProva("a"), cwd: a)
        try base.paneTerminal(20, pestanya: 2, uuid: uuidDeProva("b"), cwd: b)
        try base.paneTerminal(30, pestanya: 3, uuid: uuidDeProva("c"), cwd: inici)

        let sessions = tmp.url("sessions")
        var processos = ProcessosFalsos.ambWarp()
        try escriuSessio(a: sessions, pid: 101, sessionId: "s-101", cwd: a)
        processos.claude(101, argv: argv, uuid: uuidDeProva("a"))

        let lector = Lector(rutaWarp: base.url, rutaAjustos: tmp.url("settings.toml"), carpetaSessions: sessions,
                            processos: processos, warp: { .perOmissio }, inici: inici)
        let ids = IdsDeProva()
        entorn = EntornCLI(lector: lector, inici: inici, carpetaReal: real,
                           transcripcions: LectorTranscripcions(carpeta: tmp.url("projects")),
                           confianca: LectorConfianca(ruta: tmp.url("claude.json")), nouId: { ids.nou() })
    }

    func executa(_ args: String...) -> (codi: Int32, sortida: Sortida) {
        var sortida = Sortida()
        let codi = OrdreCLI.executa(args, entorn: entorn, sortida: &sortida)
        return (codi, sortida)
    }

    func existeix(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// D-P12: el mateix, amb Warp Preview obert (pid 90) i Warp Stable instal·lat però tancat (sense l'app, pid 40).
    func ambPreview() throws -> EntornCLI {
        var entorn = self.entorn
        var processos = try #require(entorn.lector.processos as? ProcessosFalsos)
        processos.processos[40] = nil
        processos.processos[90] = (InfoProces(executable: binariPreview, argv: [binariPreview]), 1)
        entorn.lector.processos = processos
        var warp = InstallacioWarp.perOmissio
        warp.executablePreview = binariPreview
        entorn.lector.warp = { [warp] in warp }
        return entorn
    }

    /// 0.31.1: el mateix, sense cap Warp: ni Stable ni Preview (macOS no en sap res i no n'hi ha a Aplicacions), ni obert.
    func senseWarp() throws -> EntornCLI {
        var entorn = self.entorn
        var processos = try #require(entorn.lector.processos as? ProcessosFalsos)
        processos.processos[40] = nil
        processos.processos[50] = nil
        entorn.lector.processos = processos
        let warp = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: { _ in nil })
        entorn.lector.warp = { warp }
        return entorn
    }
}

private let binariPreview = "/Applications/WarpPreview.app/Contents/MacOS/preview"

@Suite struct OrdreCLITests {
    @Test func ajudaIVersio() throws {
        let e = try Escenari()
        for args in [[], ["--ajuda"], ["-h"]] {
            var sortida = Sortida()
            #expect(OrdreCLI.executa(args, entorn: e.entorn, sortida: &sortida) == 0)
            #expect(sortida.text.contains("warp-launch importa"))
            #expect(sortida.errors.isEmpty)
        }
        let (codi, sortida) = e.executa("--versio")
        #expect(codi == 0)
        #expect(sortida.text == "Warp Launch \(WarpLaunch.versio)\n")
    }

    /// L'ajuda d'`importa` diu quan queden només terminal les pestanyes on no corre Claude: sense configuració, i també amb
    /// una que encara no té cap pestanya (decisió d'en David del 08/11/2026). Abans deia que, amb configuració, sempre
    /// prenien la plantilla.
    @Test func lAjudaDImportaDiuQuanQuedenNomesTerminal() throws {
        let ajuda = OrdreCLI.ajuda.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        // Sense escriure la carpeta real: les proves no l'esmenten mai (`lesProvesNoLlegeixenLEstatReal`).
        #expect(ajuda.contains("Les pestanyes on no corre Claude prenen la plantilla de "))
        #expect(ajuda.contains(". Si no hi ha configuració, o encara no té cap pestanya, queden només terminal, com a l'app."))
    }

    @Test func usIncorrecte() throws {
        let e = try Escenari()
        for args in [["fes"], ["llegeix", "--desa"], ["importa", "--res"], ["configuracio"], ["configuracio", "mostra"],
                     ["llegeix", "--warp"], ["configuracio", "valida", "--config"],
                     ["configuracio", "valida", "--config", "relativa"],
                     ["configuracio", "valida", "--config", "/a", "--config", "/b"]] {
            var sortida = Sortida()
            #expect(OrdreCLI.executa(args, entorn: e.entorn, sortida: &sortida) == 64, "\(args)")
            #expect(sortida.errors.hasPrefix("warp-launch: "), "\(args)")
            #expect(sortida.text.isEmpty, "\(args)")
        }
    }

    @Test func llegeix() throws {
        let e = try Escenari()
        let (codi, sortida) = e.executa("llegeix")
        #expect(codi == 0)
        #expect(sortida.text.hasPrefix("Warp: 2 finestres, 3 pestanyes de terminal, 1 amb Claude."))

        let (codiJSON, json) = e.executa("llegeix", "--json")
        #expect(codiJSON == 0)
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        let lectura = try decodificador.decode(LecturaWarp.self, from: Data(json.text.utf8))
        #expect(lectura.finestres.map(\.pestanyes.count) == [2, 1])
    }

    @Test func unaBaseDeWarpQueNoEsPotLlegirEsUnaFallida() throws {
        let e = try Escenari()
        let (codi, sortida) = e.executa("importa", "--warp", e.tmp.url("no-hi-és.sqlite").path)
        #expect(codi == 1)
        #expect(sortida.errors.hasPrefix("warp-launch: "))
    }

    /// Amb la restauració de sessió desactivada, la base és d'abans: `importa` no en treu res, i `llegeix` no la mostra,
    /// llevat que se li doni una base a mà.
    @Test func ambLaRestauracioDesactivadaNoEsFiaDeLaBase() throws {
        let e = try Escenari()
        try Data("[general]\nrestore_session = false\n".utf8).write(to: e.tmp.url("settings.toml"))
        let carpeta = e.tmp.url("nova")
        let (codi, sortida) = e.executa("importa", "--desa", "--config", carpeta.path)
        #expect(codi != 0)
        #expect(sortida.errors.contains("Warp no desa les finestres"))
        // No és que Warp no tingui res: el CLI no toca l'ajust, i l'app, amb la configuració de debò, sí.
        #expect(sortida.errors.contains("«warp-launch importa» no toca aquest ajust i no pot demanar a Warp que les desi. "
            + "L'app, amb la configuració de debò, sí: l'activa uns segons perquè Warp les desi, i el torna a desactivar."))
        #expect(!sortida.errors.contains("No hi ha res per importar"))
        #expect(!e.existeix(carpeta), "no s'ha desat res")
        #expect(e.executa("llegeix").sortida.text.contains("Warp no desa les finestres"))
        #expect(e.executa("llegeix", "--warp", e.tmp.url("warp.sqlite").path).sortida.text.contains("Warp: 2 finestres"))
    }

    @Test func importaNoEscriuRes() throws {
        let e = try Escenari()
        let abans = try FileManager.default.subpathsOfDirectory(atPath: e.tmp.ruta).sorted()
        let (codi, sortida) = e.executa("importa")
        #expect(codi == 0)
        #expect(sortida.errors.isEmpty)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: e.tmp.ruta).sorted() == abans)
        #expect(!e.existeix(e.real))

        let linies = sortida.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(linies.prefix(5) == [
            "Importació de Warp (vista prèvia: no s'ha desat res)",
            "2 finestres · 3 pestanyes · 1 amb Claude, amb la seva ordre · 2 només terminal (1 sense Claude obert)",
            "1 pestanya salta els permisos (--dangerously-skip-permissions).",
            "Plantilla: la segura, sense saltar els permisos (encara no hi ha cap configuració).",
            "Les pestanyes que no tenien Claude obert queden només terminal (configuració nova).",
        ])
        // «A» conserva l'ordre del seu Claude; «B», que no en tenia, queda només terminal (D-P5a, 07/11/2026).
        #expect(sortida.text.contains("""

            projectes · 2 pestanyes · 1 amb Claude
               1  A · ~/GitHub/projectes/a · Claude, de la seva ordre
               2  B · ~/GitHub/projectes/b · sense Claude

            Finestra 2 · 1 pestanya · 0 amb Claude
               1  Pestanya 1 · ~ · sense Claude
                  ⚠ Carpeta d'inici: probablement Warp l'ha perduda

            Ordres de Claude:
               1  claude --dangerously-skip-permissions --effort ultracode

            """))
    }

    /// Sense configuració, `importa` fa com l'app en crear-la: les pestanyes on no corre Claude queden només terminal
    /// (D-P5a, en David, 07/11/2026), també en el JSON i amb `--desa`. Les que en tenen conserven la seva ordre.
    @Test func importaSenseConfiguracioDeixaNomesTerminalLesQueNoTenienClaude() throws {
        let e = try Escenari()
        let llegida = try Configuracio.llegeix(Data(e.executa("importa", "--json").sortida.text.utf8), inici: e.inici)
        let pestanyes = llegida.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyes.map(\.titol) == ["A", "B", "Pestanya 1"])
        #expect(pestanyes.map(\.claude.activat) == [true, false, false])
        #expect(pestanyes[0].claude.saltaPermisos && pestanyes[0].claude.ultracode, "«A», amb la seva ordre")
        #expect(pestanyes[1].claude == .nomesTerminal)

        let carpeta = e.tmp.url("nova")
        #expect(e.executa("importa", "--desa", "--config", carpeta.path).codi == 0)
        let desada = try #require(try MagatzemConfiguracio(carpeta: carpeta, inici: e.inici).carrega()).configuracio
        #expect(desada.finestres.flatMap(\.pestanyes).map(\.claude.activat) == [true, false, false])
        #expect(desada.plantilla == .perOmissio)
        #expect(!e.existeix(e.real))
    }

    /// Sense configuració, les pestanyes on no corre Claude no salten els permisos ni porten ultracode (D11, revisada per
    /// en David el 07/11/2026). Les que ja tenen Claude conserven la seva ordre.
    @Test func importaSenseConfiguracioNoSaltaElsPermisos() throws {
        let e = try Escenari(argv: ["claude"])
        let (codi, sortida) = e.executa("importa")
        #expect(codi == 0)
        #expect(sortida.text.contains("0 pestanyes salten els permisos"))
        #expect(sortida.text.contains("\nOrdres de Claude:\n   1  claude\n"), "«A», sense saltar els permisos; «B» és terminal")
        #expect(!sortida.text.contains("ultracode"))

        let llegida = try Configuracio.llegeix(Data(e.executa("importa", "--json").sortida.text.utf8), inici: e.inici)
        let ambClaude = llegida.configuracio.finestres.flatMap(\.pestanyes).filter(\.claude.activat)
        #expect(ambClaude.map(\.titol) == ["A"])
        #expect(ambClaude.allSatisfy { !$0.claude.saltaPermisos && !$0.claude.ultracode && !$0.claude.enBypass })
        #expect(!e.existeix(e.real))
    }

    /// Amb configuració real, `importa` en pren la plantilla, com l'app (`Editor.plantillaPerImportar`); i, amb
    /// `--desa`, la desa amb aquesta plantilla. La configuració real no canvia.
    @Test func importaAmbConfiguracioEnPrenLaPlantilla() throws {
        let e = try Escenari(argv: ["claude"])
        var plantilla = ClaudePestanya.habituals
        plantilla.model = "opus"
        let real = MagatzemConfiguracio(carpeta: e.real, inici: e.inici)
        let feta = Pestanya(id: uuid(2), titol: "Feta", carpeta: "\(e.inici)/GitHub/projectes/a", claude: plantilla)
        try real.desa(Configuracio(plantilla: plantilla, finestres: [Finestra(id: uuid(1), nom: "f", pestanyes: [feta])]),
                      sobre: nil)
        let abans = try Data(contentsOf: real.fitxer)

        let (codi, sortida) = e.executa("importa")
        #expect(codi == 0)
        #expect(sortida.text.contains("1 pestanya salta els permisos"))
        #expect(sortida.text.contains("Plantilla: la de \(real.fitxer.path)."))
        // Tornar a importar no canvia (D11): «B», que no tenia Claude obert, pren la plantilla.
        #expect(sortida.text.contains(" · 2 amb Claude (1 amb la seva ordre, 1 amb la plantilla) · 1 només terminal\n"))
        #expect(!sortida.text.contains("queden només terminal"))
        #expect(sortida.text.contains("   1  claude --dangerously-skip-permissions --model opus --effort ultracode\n"))

        let carpeta = e.tmp.url("nova")
        #expect(e.executa("importa", "--desa", "--config", carpeta.path).codi == 0)
        let desada = try #require(try MagatzemConfiguracio(carpeta: carpeta, inici: e.inici).carrega()).configuracio
        #expect(desada.plantilla == plantilla)
        #expect(desada.finestres[0].pestanyes[1].claude == plantilla.perAPestanyaNova())
        #expect(try Data(contentsOf: real.fitxer) == abans)
    }

    /// Una configuració real sense cap pestanya (després de «Comença en blanc», o amb una finestra buida) és com una de
    /// nova, com a l'app (decisió d'en David del 08/11/2026): les pestanyes on no corre Claude queden només terminal, amb
    /// la plantilla de la configuració si s'hi activa Claude. La configuració real no canvia.
    @Test func importaAmbUnaConfiguracioSensePestanyesEsComUnaDeNova() throws {
        let e = try Escenari(argv: ["claude"])
        var plantilla = ClaudePestanya.habituals
        plantilla.model = "opus"
        let real = MagatzemConfiguracio(carpeta: e.real, inici: e.inici)
        try real.desa(Configuracio(plantilla: plantilla, finestres: [Finestra(id: uuid(1), nom: "buida")]), sobre: nil)
        let abans = try Data(contentsOf: real.fitxer)

        let (codi, sortida) = e.executa("importa")
        #expect(codi == 0)
        #expect(sortida.text.contains("Plantilla: la de \(real.fitxer.path).\n"
            + "Les pestanyes que no tenien Claude obert queden només terminal (la configuració encara no té cap pestanya).\n"))
        #expect(sortida.text.contains("2 finestres · 3 pestanyes · 1 amb Claude, amb la seva ordre · 2 només terminal "
            + "(1 sense Claude obert)\n"))
        let llegida = try Configuracio.llegeix(Data(e.executa("importa", "--json").sortida.text.utf8), inici: e.inici)
        let pestanyes = llegida.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyes.map(\.claude.activat) == [true, false, false])
        var apagada = plantilla.perAPestanyaNova()
        apagada.activat = false
        #expect(pestanyes[1].claude == apagada, "«B», només terminal, amb la plantilla de la configuració")
        #expect(llegida.configuracio.plantilla == plantilla)
        #expect(try Data(contentsOf: real.fitxer) == abans)
    }

    /// Una configuració real que no es pot llegir no atura la vista prèvia: la plantilla segura, i diu per què.
    @Test func importaAmbLaConfiguracioMalmesaFaServirLaSegura() throws {
        let e = try Escenari(argv: ["claude"])
        let real = MagatzemConfiguracio(carpeta: e.real, inici: e.inici)
        try FileManager.default.createDirectory(at: e.real, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: real.fitxer)

        let (codi, sortida) = e.executa("importa")
        #expect(codi == 0)
        #expect(sortida.text.contains("Plantilla: la segura, sense saltar els permisos (no s'ha pogut llegir \(real.fitxer.path): "))
        #expect(sortida.text.contains("0 pestanyes salten els permisos"))
        // Hi ha configuració, encara que no es pugui llegir: com si es tornés a importar, «B» pren la plantilla.
        #expect(sortida.text.contains(" · 2 amb Claude (1 amb la seva ordre, 1 amb la plantilla) · 1 només terminal\n"))
        #expect(try Data(contentsOf: real.fitxer) == Data("{".utf8))
    }

    @Test func importaEnJSONEsLaConfiguracioQueEsDesaria() throws {
        let e = try Escenari()
        let (codi, sortida) = e.executa("importa", "--json")
        #expect(codi == 0)
        let llegida = try Configuracio.llegeix(Data(sortida.text.utf8), inici: e.inici)
        #expect(llegida.avisos.isEmpty)
        #expect(llegida.configuracio.generador == "Warp Launch \(WarpLaunch.versio)")
        #expect(llegida.configuracio.plantilla == .perOmissio)
        #expect(llegida.configuracio.finestres.map(\.nom) == ["projectes", "Finestra 2"])
        #expect(!e.existeix(e.real))
    }

    @Test func desaNomesAUnaCarpetaDeProva() throws {
        let e = try Escenari()
        // Sense --config, o amb la carpeta real (també a través d'un enllaç, amb altres majúscules o a dins): no.
        try FileManager.default.createDirectory(at: e.real, withIntermediateDirectories: true)
        let enllac = e.tmp.url("enllac")
        try FileManager.default.createSymbolicLink(at: enllac, withDestinationURL: e.real)
        for args in [["importa", "--desa"], ["importa", "--config", "/tmp/x"],
                     ["importa", "--desa", "--config", e.real.path], ["importa", "--desa", "--config=\(e.real.path)"],
                     ["importa", "--desa", "--config", enllac.path],
                     ["importa", "--desa", "--config", e.real.path.uppercased()],
                     ["importa", "--desa", "--config", e.real.appending(path: "copies").path],
                     ["importa", "--desa", "--config", "~/config-real"]] {
            var sortida = Sortida()
            #expect(OrdreCLI.executa(args, entorn: e.entorn, sortida: &sortida) == 64, "\(args)")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.real.path).isEmpty)
    }

    @Test func desaNomesAUnaCarpetaDeProvaEncaraQueLaRealNoExisteixi() throws {
        let e = try Escenari()
        #expect(!e.existeix(e.real))
        // La carpeta pare de la real, a través d'un enllaç i de /System/Volumes/Data.
        let enllacPare = e.tmp.url("enllac-pare")
        try FileManager.default.createSymbolicLink(at: enllacPare, withDestinationURL: e.real.deletingLastPathComponent())
        let trencat = e.tmp.url("trencat")
        try FileManager.default.createSymbolicLink(at: trencat, withDestinationURL: e.real)
        for config in [enllacPare.appending(path: "config-real").path, "/System/Volumes/Data" + e.real.path,
                       e.real.path.uppercased(), e.real.appending(path: "a/b").path, enllacPare.appending(path: "CONFIG-REAL/x").path,
                       e.tmp.url("no-hi-és/../inici/config-real").path, trencat.path, trencat.appending(path: "x").path] {
            var sortida = Sortida()
            #expect(OrdreCLI.executa(["importa", "--desa", "--config", config], entorn: e.entorn, sortida: &sortida) == 64,
                    "\(config)")
        }
        #expect(!e.existeix(e.real))
        // Una carpeta germana sí.
        var sortida = Sortida()
        #expect(OrdreCLI.executa(["importa", "--desa", "--config", e.real.path + "-prova"], entorn: e.entorn,
                                 sortida: &sortida) == 0)
        #expect(!e.existeix(e.real))
    }

    @Test func importaAmbErrorsSurtAmbElCodi2() throws {
        let e = try Escenari(argv: ["claude", "--permission-mode", "yolo"])
        let (codi, sortida) = e.executa("importa")
        #expect(codi == 2)
        #expect(sortida.text.contains("✗ Claude no arrencarà: el mode de permisos «yolo» no existeix"))
        #expect(sortida.text.hasSuffix("\n1 pestanya no s'obriria com diu la configuració (✗).\n"))
        let (codiJSON, _) = e.executa("importa", "--json")
        #expect(codiJSON == 2)
    }

    @Test func desaIValida() throws {
        let e = try Escenari()
        let carpeta = e.tmp.url("prova")
        let (codi, sortida) = e.executa("importa", "--desa", "--config", carpeta.path)
        #expect(codi == 0)
        #expect(sortida.text.hasPrefix("Importació de Warp, desada a \(carpeta.path)/configuracio.json\n"))
        let magatzem = MagatzemConfiguracio(carpeta: carpeta, inici: e.inici)
        let carregada = try #require(try magatzem.carrega())
        #expect(carregada.configuracio.finestres.flatMap(\.pestanyes).count == 3)

        // Una segona vegada no la trepitja.
        let (codi2, sortida2) = e.executa("importa", "--desa", "--config", carpeta.path)
        #expect(codi2 == 1)
        #expect(sortida2.errors.contains("ja hi ha una configuració"))
        #expect(try magatzem.carrega()?.empremta == carregada.empremta)

        let (codi3, valida) = e.executa("configuracio", "valida", "--config", carpeta.path)
        #expect(codi3 == 0)
        #expect(valida.text.hasPrefix("""
            Configuració: \(carpeta.path)/configuracio.json
            2 finestres · 3 pestanyes · 1 amb Claude · 2 només terminal

            """))
        #expect(valida.text.hasSuffix("\nResultat: 0 errors, 1 avís.\n"))
    }

    @Test func validaDiuElsErrors() throws {
        let e = try Escenari()
        let carpeta = e.tmp.url("prova")
        let magatzem = MagatzemConfiguracio(carpeta: carpeta, inici: e.inici)
        var claude = ClaudePestanya.habituals
        claude.modePermisos = "yolo"
        let configuracio = Configuracio(plantilla: .habituals, finestres: [Finestra(id: uuid(1), nom: "A", pestanyes: [
            Pestanya(id: uuid(2), titol: "P", carpeta: e.inici + "/GitHub/projectes/a", claude: claude),
        ])])
        try magatzem.desa(configuracio, sobre: nil)
        let (codi, sortida) = e.executa("configuracio", "valida", "--config", carpeta.path)
        #expect(codi == 2)
        #expect(sortida.text.contains("""
               1  P · ~/GitHub/projectes/a · Claude
                  ✗ Claude no arrencarà: el mode de permisos «yolo» no existeix (acceptEdits, auto, bypassPermissions, manual, dontAsk, plan)
                  ⚠ Amb «Salta els permisos», Claude no fa cas del mode «yolo»
            """))
        #expect(sortida.text.hasSuffix("\nResultat: 1 error, 1 avís.\n"))
    }

    @Test func validaSenseConfiguracioOAmbUnFitxerMalmes() throws {
        let e = try Escenari()
        // Per defecte, la real; aquí no n'hi ha.
        let (codi, sortida) = e.executa("configuracio", "valida")
        #expect(codi == 1)
        #expect(sortida.errors == "warp-launch: no hi ha cap configuració a \(e.real.path)/configuracio.json\n")
        #expect(!e.existeix(e.real))

        try FileManager.default.createDirectory(at: e.real, withIntermediateDirectories: true)
        try Data("{\n  \"versio\": 1,\n  x\n}".utf8).write(to: e.real.appending(path: "configuracio.json"))
        let (codi2, sortida2) = e.executa("configuracio", "valida")
        #expect(codi2 == 1)
        #expect(sortida2.errors.contains("el fitxer no és JSON vàlid (línia 3"))
    }

    // MARK: - obre (mode de prova, D17)

    /// «Feina»: A (oberta: el seu pane és a Warp), B2 (reprèn la seva conversa), Docs (terminal, a la carpeta d'A) i
    /// Perduda (la carpeta no existeix); i «Altres». `estat.json` lliga A al pane «a» i B2 a la seva conversa, que té
    /// transcripció; `claude.json` confia en la carpeta «a».
    private func ambConfiguracio(_ e: Escenari, finestres extra: [Finestra] = [],
                                 vincles: [UUID: VincleEstat] = [:]) throws -> URL {
        let a = e.inici + "/GitHub/projectes/a"
        let b = e.inici + "/GitHub/projectes/b"
        let carpeta = e.tmp.url("prova")
        try MagatzemConfiguracio(carpeta: carpeta, inici: e.inici).desa(Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: uuid(1), nom: "Feina", pestanyes: [
                Pestanya(id: uuid(2), titol: "A", carpeta: a, claude: .habituals),
                Pestanya(id: uuid(3), titol: "B2", carpeta: b, claude: .habituals),
                Pestanya(id: uuid(4), titol: "Docs", carpeta: a, claude: ClaudePestanya(activat: false)),
                Pestanya(id: uuid(5), titol: "Perduda", carpeta: e.inici + "/no-hi-es", claude: .habituals),
            ]),
            Finestra(id: uuid(6), nom: "Altres", pestanyes: [Pestanya(id: uuid(7), titol: "X", carpeta: b, claude: .habituals)]),
        ] + extra), sobre: nil)
        let vista = Date(timeIntervalSince1970: 1_793_750_400)
        try EstatApp(pestanyes: [
            uuid(2): VincleEstat(pane: uuidDeProva("a"), origen: .importacio, vista: vista),
            uuid(3): VincleEstat(sessio: conversaB2, origen: .importacio, vista: vista),
        ].merging(vincles) { _, nou in nou }).json().write(to: carpeta.appending(path: EstatApp.nomFitxer))
        let projecte = e.tmp.url("projects").appending(path: try #require(LectorTranscripcions.projecte(b)))
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        try Data().write(to: projecte.appending(path: conversaB2 + ".jsonl"))
        try Data(#"{"projects": {"\#(a)": {"hasTrustDialogAccepted": true}}}"#.utf8).write(to: e.tmp.url("claude.json"))
        return carpeta
    }

    private let conversaB2 = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"

    /// Tots els fitxers de la carpeta temporal, amb el contingut: el mode de prova no hi ha de canviar res.
    private func instantania(_ e: Escenari) throws -> [String: Data] {
        let gestor = FileManager.default
        var fitxers: [String: Data] = [:]
        for cami in gestor.enumerator(atPath: e.tmp.ruta)?.allObjects as? [String] ?? [] {
            let ruta = e.tmp.ruta + "/" + cami
            var carpeta: ObjCBool = false
            gestor.fileExists(atPath: ruta, isDirectory: &carpeta)
            fitxers[cami] = carpeta.boolValue ? Data() : try Data(contentsOf: URL(filePath: ruta))
        }
        return fitxers
    }

    /// El mode de prova diu la mateixa conversa que el full: la més recent de la carpeta (D7).
    @Test func obreMostraLaConversaMesRecent() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let projecte = e.tmp.url("projects").appending(path: try #require(LectorTranscripcions.projecte(e.inici + "/GitHub/projectes/b")))
        let recent = "7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8).write(to: projecte.appending(path: recent + ".jsonl"))
        let (_, sortida) = e.executa("obre", "feina", "--config", carpeta.path)
        #expect(sortida.text.contains("B2 · ~/GitHub/projectes/b · Claude, reprèn 7a8b9c0d"), "\(sortida.text)")
    }

    @Test func obreNomesMostraElPla() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let abans = try instantania(e)
        let (codi, sortida) = e.executa("obre", " feina ", "--config", carpeta.path)
        #expect(codi == 2, "Perduda no s'obriria")
        #expect(sortida.errors.isEmpty)
        #expect(sortida.text.hasPrefix("""
            Mode de prova: no s'ha escrit ni obert res.
            Finestra 1 de 2: «Feina» (\(carpeta.path)/configuracio.json)
            Warp és obert.
            S'obrirà 1 finestra nova de Warp amb 2 pestanyes: 1 amb Claude (1 reprèn la seva conversa) i 1 només terminal · unes 0,5 GB · ja obertes: 1 · no s'obriran: 1

            Ja obertes (1):
               1  A · ~/GitHub/projectes/a · oberta a Warp (finestra 1 › A)

            No s'obriran (1):
               4  Perduda · ~/no-hi-es · ✗ la carpeta no existeix

            S'obririen (2):
               2  B2 · ~/GitHub/projectes/b · Claude, reprèn 1b2c3d4e
               3  Docs · ~/GitHub/projectes/a · només terminal

            Avisos:
              ⚠ B2: Claude preguntarà si confies en la carpeta: la pestanya esperarà una tecla
              ⚠ Docs: potser ja és oberta a Warp (finestra 1 › A): és a la mateixa carpeta

            Fitxer per a Warp: warp-launch-
            """), "\(sortida.text)")
        #expect(sortida.text.contains("\nURL: warp://launch/warp-launch-"))
        #expect(sortida.text.contains("""
            exec: " WARP_LAUNCH_PESTANYA=00000000-0000-0000-0000-000000000003 CLAUDE_ENV_FILE=\(carpeta.path)/entorn-claude.sh claude --dangerously-skip-permissions --effort ultracode --resume \(conversaB2)"
            """))
        #expect(!sortida.text.contains("--continue"))
        #expect(try instantania(e) == abans, "no ha d'escriure res, tampoc estat.json")

        // En JSON, el mateix.
        let (codi2, json) = e.executa("obre", "1", "--json", "--config", carpeta.path)
        #expect(codi2 == 2)
        let objecte = try #require(try JSONSerialization.jsonObject(with: Data(json.text.utf8)) as? [String: Any])
        #expect(objecte["mode"] as? String == "prova")
        #expect((objecte["aObrir"] as? [[String: Any]])?.compactMap { $0["conversa"] as? String } == ["repren", "terminal"])
        #expect((objecte["obertes"] as? [Any])?.count == 1)
        #expect(((objecte["fitxer"] as? [String: Any])?["url"] as? String)?.hasPrefix("warp://launch/warp-launch-") == true)
        #expect(try instantania(e) == abans)
    }

    /// Una finestra on tot és obert (aquí, perquè la seva conversa és viva a Warp): codi 0, i cap fitxer.
    @Test func obreSenseResPerObrir() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e, finestres: [
            Finestra(id: uuid(8), nom: "Oberta", pestanyes: [
                Pestanya(id: uuid(10), titol: "A bis", carpeta: e.inici + "/GitHub/projectes/a", claude: .habituals),
            ]),
        ], vincles: [uuid(10): VincleEstat(sessio: "s-101", origen: .importacio, vista: Date(timeIntervalSince1970: 0))])
        let (codi, sortida) = e.executa("obre", "Oberta", "--config", carpeta.path)
        #expect(codi == 0)
        #expect(sortida.text.contains("""
            No s'obrirà res. · ja obertes: 1

            Ja obertes (1):
               1  A bis · ~/GitHub/projectes/a · la seva conversa és oberta a Warp (finestra 1 › A)

            """), "\(sortida.text)")
        #expect(!sortida.text.contains("Fitxer per a Warp"))
    }

    @Test func obreAmbErrors() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e, finestres: [Finestra(id: uuid(9), nom: "altres ", pestanyes: [])])
        for (args, missatge) in [
            (["obre"], "falta la finestra"),
            (["obre", "--config", carpeta.path], "falta la finestra"),
            (["obre", "4", "--config", carpeta.path], "no hi ha cap finestra número 4; n'hi ha 3:\n  1. Feina\n  2. Altres"),
            (["obre", "Prova", "--config", carpeta.path], "no hi ha cap finestra «Prova»"),
            (["obre", "ALTRES", "--config", carpeta.path], "hi ha més d'una finestra «ALTRES» (2, 3): tria-la pel número"),
            (["obre", "1", "--obre", "--config", carpeta.path], "«--obre» només funciona amb la comanda «warp-launch» de debò"),
            (["obre", "1", "--desa", "--config", carpeta.path], "opció desconeguda per a obre: «--desa»"),
        ] {
            var sortida = Sortida()
            #expect(OrdreCLI.executa(args, entorn: e.entorn, sortida: &sortida) == 64, "\(args)")
            #expect(sortida.errors.contains(missatge), "\(sortida.errors)")
            #expect(sortida.text.isEmpty)
        }
        // Sense configuració (per defecte, la real): 1.
        let (codi, sortida) = e.executa("obre", "1")
        #expect(codi == 1)
        #expect(sortida.errors == "warp-launch: no hi ha cap configuració a \(e.real.path)/configuracio.json\n")
        #expect(!e.existeix(e.real))
    }

    /// D-P12: amb Warp Preview obert i Warp Stable tancat, `llegeix` i `obre` ho diuen, i `obre` surt amb 1 (amb `--obre`,
    /// no s'obriria res). No s'escriu res.
    @Test func ambWarpPreviewLlegeixIObreHoDiuen() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let entorn = try e.ambPreview()
        let abans = try instantania(e)
        func executa(_ args: String...) -> (Int32, Sortida) {
            var sortida = Sortida()
            return (OrdreCLI.executa(args, entorn: entorn, sortida: &sortida), sortida)
        }
        let avis = "Warp Preview encara no és compatible: cal Warp Stable. Ara és obert Warp Preview, i Warp Stable no: "
            + "obre Warp Stable i torna-ho a provar."
        let (codiLlegeix, llegeix) = executa("llegeix")
        #expect(codiLlegeix == 0)
        #expect(llegeix.text.contains("Warp és tancat: són les finestres que restaurarà en obrir-se.\n⚠ \(avis)\n"), "\(llegeix.text)")

        let (codi, sortida) = executa("obre", "feina", "--config", carpeta.path)
        #expect(codi == 1)
        // Just després de la finestra, i sense dir que primer s'obriria Warp: no s'obriria res, tampoc Warp Stable.
        let linies = sortida.text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(linies.count > 2 && linies[1].hasPrefix("Finestra ") && linies[2] == "✗ \(avis) No s'obriria res.",
                "\(sortida.text)")
        #expect(!sortida.text.contains("primer s'obriria Warp") && !sortida.text.contains("Warp és tancat"), "\(sortida.text)")
        // Sense Warp Preview i amb Warp Stable tancat, sí que ho diu.
        var tancat = e.entorn
        var processos = try #require(tancat.lector.processos as? ProcessosFalsos)
        processos.processos[40] = nil
        tancat.lector.processos = processos
        var sortidaTancat = Sortida()
        #expect(OrdreCLI.executa(["obre", "feina", "--config", carpeta.path], entorn: tancat, sortida: &sortidaTancat) != 1)
        #expect(sortidaTancat.text.contains("\nWarp és tancat: primer s'obriria Warp.\n"), "\(sortidaTancat.text)")
        #expect(!sortidaTancat.text.contains("Preview"), "\(sortidaTancat.text)")
        let (codiJSON, json) = executa("obre", "feina", "--json", "--config", carpeta.path)
        #expect(codiJSON == 1)
        let objecte = try #require(try JSONSerialization.jsonObject(with: Data(json.text.utf8)) as? [String: Any])
        #expect(objecte["warpPreview"] as? String == avis)
        #expect(try instantania(e) == abans)
        // Sense Warp Preview, el JSON no en diu res.
        let (_, net) = e.executa("obre", "feina", "--json", "--config", carpeta.path)
        #expect(try #require(try JSONSerialization.jsonObject(with: Data(net.text.utf8)) as? [String: Any])["warpPreview"] == nil)
    }

    /// 0.31.1: sense cap Warp (ni Stable ni Preview), `llegeix` i `obre` ho diuen, i `obre` surt amb 1 sense dir que primer
    /// s'obriria Warp (abans ho deia, i amb `--obre` fallava). No s'escriu res.
    @Test func senseCapWarpLlegeixIObreHoDiuen() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let entorn = try e.senseWarp()
        let abans = try instantania(e)
        func executa(_ args: String...) -> (Int32, Sortida) {
            var sortida = Sortida()
            return (OrdreCLI.executa(args, entorn: entorn, sortida: &sortida), sortida)
        }
        let avis = "No s'ha trobat Warp en aquest Mac: cal Warp Stable."
        let (codiLlegeix, llegeix) = executa("llegeix")
        #expect(codiLlegeix == 0)
        #expect(llegeix.text.contains("Warp és tancat: són les finestres que restaurarà en obrir-se.\n⚠ \(avis)\n"), "\(llegeix.text)")

        let (codi, sortida) = executa("obre", "feina", "--config", carpeta.path)
        #expect(codi == 1)
        let linies = sortida.text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(linies.count > 2 && linies[1].hasPrefix("Finestra ") && linies[2] == "✗ \(avis) No s'obriria res.",
                "\(sortida.text)")
        #expect(!sortida.text.contains("primer s'obriria Warp") && !sortida.text.contains("Warp és tancat"), "\(sortida.text)")
        let (codiJSON, json) = executa("obre", "feina", "--json", "--config", carpeta.path)
        #expect(codiJSON == 1)
        let objecte = try #require(try JSONSerialization.jsonObject(with: Data(json.text.utf8)) as? [String: Any])
        #expect(objecte["warpPreview"] as? String == avis)
        #expect(try instantania(e) == abans)
    }

    /// 0.31.1: en un Mac on no s'ha instal·lat mai Warp, tampoc no hi ha `warp.sqlite` (ni `settings.toml`, i per tant la
    /// base es llegeix). `llegeix`, `importa` i `obre` diuen que no hi ha Warp, no només que no troben la base. Amb només
    /// Warp Preview, el seu text; amb Warp Stable, l'error de sempre.
    @Test func senseCapWarpNiBaseHoDiuen() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let senseBase = e.tmp.url("no-hi-es.sqlite")
        var entorn = try e.senseWarp()
        entorn.lector.rutaWarp = senseBase
        func executa(_ entorn: EntornCLI, _ args: [String]) -> (Int32, Sortida) {
            var sortida = Sortida()
            return (OrdreCLI.executa(args, entorn: entorn, sortida: &sortida), sortida)
        }
        let ordres = [["llegeix"], ["llegeix", "--json"], ["importa"], ["obre", "feina", "--config", carpeta.path],
                      ["obre", "feina", "--json", "--config", carpeta.path]]
        let base = "Tampoc no hi ha la base de Warp (\(senseBase.path))."
        let abans = try instantania(e)
        for args in ordres {
            let (codi, sortida) = executa(entorn, args)
            #expect(codi == 1, "\(args)")
            #expect(sortida.text.isEmpty && sortida.errors == "warp-launch: \(WarpPreview.capWarp.text) \(base)\n",
                    "\(args): \(sortida.errors)")
        }
        // Només Warp Preview: el seu text.
        let tmp = e.tmp
        var preview = InstallacioWarp.troba(aplicacions: tmp.url("Applications/Warp.app"), cerca: { _ in nil })
        preview.executablePreview = binariPreview
        entorn.lector.warp = { [preview] in preview }
        for args in ordres {
            #expect(executa(entorn, args).1.errors == "warp-launch: \(WarpPreview.nomesPreview.text) \(base)\n", "\(args)")
        }
        // Amb Warp Stable, no és que no hi hagi Warp: que encara no hi ha desat res (a sota,
        // `ambWarpStableSenseBaseDiuQueNoHiHaDesatRes`).
        var stable = e.entorn
        stable.lector.rutaWarp = senseBase
        for args in ordres {
            let (codi, sortida) = executa(stable, args)
            #expect(codi == 1 && sortida.errors == "warp-launch: \(LecturaWarp.senseBase(warpObert: true))\n",
                    "\(args): \(sortida.errors)")
        }
        #expect(try instantania(e) == abans)
    }

    /// Warp Stable instal·lat i que no s'ha obert mai en aquest usuari: no hi ha la base. `llegeix`, `importa` i `obre`
    /// diuen el mateix que l'app (`LecturaWarp.senseBase`), amb Warp tancat i amb Warp obert, i no «no trobo la base de
    /// Warp». No escriuen res. Amb una base triada a mà (`--warp`) que no hi és, l'error de sempre.
    @Test func ambWarpStableSenseBaseDiuQueNoHiHaDesatRes() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        for fitxer in ["warp.sqlite", "warp.sqlite-wal", "warp.sqlite-shm"] where e.existeix(e.tmp.url(fitxer)) {
            try FileManager.default.removeItem(at: e.tmp.url(fitxer))
        }
        let abans = try instantania(e)
        let ordres = [["llegeix"], ["llegeix", "--json"], ["importa"], ["obre", "feina", "--config", carpeta.path],
                      ["obre", "feina", "--json", "--config", carpeta.path]]
        func executa(_ entorn: EntornCLI, _ args: [String]) -> (Int32, Sortida) {
            var sortida = Sortida()
            return (OrdreCLI.executa(args, entorn: entorn, sortida: &sortida), sortida)
        }
        var tancat = e.entorn
        var processos = try #require(tancat.lector.processos as? ProcessosFalsos)
        processos.processos[40] = nil
        tancat.lector.processos = processos
        for (entorn, obert) in [(e.entorn, true), (tancat, false)] {
            #expect(entorn.lector.warpObert() == obert && entorn.lector.senseWarpStable() == nil)
            for args in ordres {
                let (codi, sortida) = executa(entorn, args)
                #expect(codi == 1 && sortida.text.isEmpty, "\(args)")
                #expect(sortida.errors == "warp-launch: \(LecturaWarp.senseBase(warpObert: obert))\n",
                        "\(args), obert: \(obert): \(sortida.errors)")
                #expect(!sortida.errors.contains("no trobo la base"))
            }
        }
        #expect(LecturaWarp.senseBase(warpObert: false).hasSuffix(": obre'l un cop i torna-ho a provar."))

        // Una base triada a mà: no és la de Warp, i no se sap si Warp hi ha desat res.
        let triada = e.tmp.url("triada.sqlite")
        for args in [["llegeix", "--warp", triada.path], ["importa", "--warp", triada.path],
                     ["obre", "feina", "--warp", triada.path, "--config", carpeta.path]] {
            let (codi, sortida) = executa(e.entorn, args)
            #expect(codi == 1 && sortida.errors == "warp-launch: no trobo la base de Warp: \(triada.path)\n",
                    "\(args): \(sortida.errors)")
        }
        #expect(try instantania(e) == abans)
    }

    /// Un `estat.json` malmès o d'una versió més nova: l'app no obriria res, i el CLI no el toca.
    @Test func obreAmbUnEstatQueNoEsPotLlegir() throws {
        let e = try Escenari()
        let carpeta = try ambConfiguracio(e)
        let fitxer = carpeta.appending(path: EstatApp.nomFitxer)
        for text in ["{no és json", #"{"versio": 2}"#] {
            try Data(text.utf8).write(to: fitxer)
            let (codi, sortida) = e.executa("obre", "1", "--config", carpeta.path)
            #expect(codi == 1)
            #expect(sortida.errors.hasPrefix("warp-launch: \(fitxer.path): «estat.json» "))
            #expect(sortida.errors.hasSuffix("; l'app no obriria res\n"))
            #expect(try Data(contentsOf: fitxer) == Data(text.utf8))
        }
    }
}

// MARK: - obre --obre (D17)

/// El rellotge de la prova: l'avança l'espera de l'obridor fals.
private final class RellotgeCLI: @unchecked Sendable {
    var ara = Date(timeIntervalSince1970: 1_793_750_400)
}

/// Un obridor que no obre res: apunta les URL, i pot fer «aparèixer» la finestra nova a la base de prova.
@MainActor
private final class ObridorFals {
    let fitxers: FitxersLaunchWarp
    let rellotge = RellotgeCLI()
    var urls: [URLLlancament] = []
    var engegades = 0
    var fallaEngegar = false
    var appOberta = false
    /// Els fitxers de la «carpeta de Warp» quan s'ha demanat obrir.
    var fitxersEnObrir: [String] = []
    var mentreObre: () throws -> Void = {}
    /// El que s'ha mostrat abans d'acabar (`avisa`).
    var mostrat = ""
    /// El que s'ha de fer si es prem Ctrl-C ara.
    var interrupcio: (@MainActor () -> Void)?

    init(_ e: Escenari) throws {
        let carpeta = e.tmp.url("warp-launch-configurations")
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        fitxers = FitxersLaunchWarp(carpeta: carpeta)
    }

    var obridor: ObridorCLI {
        ObridorCLI(obre: { [unowned self] url in
                       urls.append(url)
                       fitxersEnObrir = (try? FileManager.default.contentsOfDirectory(atPath: fitxers.carpeta.path)) ?? []
                       try mentreObre()
                   },
                   engega: { [unowned self] in
                       engegades += 1
                       if fallaEngegar { throw NoEngega() }
                   },
                   fitxers: fitxers, appOberta: { [unowned self] in appOberta },
                   espera: { [rellotge] durada in rellotge.ara += Double(durada.components.seconds) + 0.5 },
                   avisa: { [unowned self] in mostrat += $0 },
                   enInterrupcio: { [unowned self] in interrupcio = $0 })
    }

    var fitxersWarp: [String] { (try? FileManager.default.contentsOfDirectory(atPath: fitxers.carpeta.path)) ?? [] }

    func executa(_ e: Escenari, _ args: String...) async -> (codi: Int32, sortida: Sortida) {
        var entorn = e.entorn
        let rellotge = rellotge
        entorn.ara = { rellotge.ara }
        var sortida = Sortida()
        let codi = await OrdreCLI.executa(args, entorn: entorn, obridor: obridor, sortida: &sortida)
        return (codi, sortida)
    }
}

private struct NoEngega: Error, CustomStringConvertible {
    var description: String { "macOS no l'obre" }
}

@MainActor
@Suite struct OrdreCLIObreTests {
    /// La mateixa configuració que les proves del mode de prova (`ambConfiguracio`): «Feina» té A oberta, B2 i Docs per
    /// obrir, i Perduda exclosa.
    private func configuracio(_ e: Escenari) throws -> URL {
        let a = e.inici + "/GitHub/projectes/a"
        let b = e.inici + "/GitHub/projectes/b"
        let carpeta = e.tmp.url("prova")
        try MagatzemConfiguracio(carpeta: carpeta, inici: e.inici).desa(Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: uuid(1), nom: "Feina", pestanyes: [
                Pestanya(id: uuid(2), titol: "A", carpeta: a, claude: .habituals),
                Pestanya(id: uuid(3), titol: "B2", carpeta: b, claude: .habituals),
                Pestanya(id: uuid(4), titol: "Docs", carpeta: a, claude: ClaudePestanya(activat: false)),
            ]),
            Finestra(id: uuid(6), nom: "Oberta", pestanyes: [Pestanya(id: uuid(7), titol: "A", carpeta: a, claude: .habituals)]),
        ]), sobre: nil)
        try EstatApp(pestanyes: [
            uuid(2): VincleEstat(pane: uuidDeProva("a"), origen: .importacio, vista: Date(timeIntervalSince1970: 0)),
            uuid(7): VincleEstat(sessio: "s-101", origen: .importacio, vista: Date(timeIntervalSince1970: 0)),
        ]).json().write(to: carpeta.appending(path: EstatApp.nomFitxer))
        return carpeta
    }

    /// Obre B2 i Docs pel mateix camí que l'app: desa el llançament, escriu el fitxer, el passa a Warp, veu la finestra
    /// nova, esborra el fitxer i lliga els panes. El Claude de B2 no arrenca (la prova no en té): ho diu, amb codi 1.
    @Test func obreLaFinestraIHoDiu() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        o.mentreObre = {
            let base = try BaseWarpDeProva(a: e.tmp.url("warp.sqlite"), crea: false)
            try base.finestra(3)
            try base.pestanya(4, finestra: 3, titol: "B2")
            try base.pestanya(5, finestra: 3, titol: "Docs")
            try base.paneTerminal(40, pestanya: 4, uuid: uuidDeProva("d"), cwd: e.inici + "/GitHub/projectes/b")
            try base.paneTerminal(50, pestanya: 5, uuid: uuidDeProva("e"), cwd: e.inici + "/GitHub/projectes/a")
        }
        let (codi, sortida) = await o.executa(e, "obre", "Feina", "--obre", "--config", carpeta.path)
        #expect(codi == 1, "\(sortida.errors)")
        #expect(o.mostrat.hasPrefix("S'obre a Warp (--obre).\n"), "\(o.mostrat)")
        #expect(o.interrupcio == nil, "en acabar, Ctrl-C ja no ha de fer res")
        #expect(sortida.text.contains("S'ha obert «Feina» a Warp: 2 pestanyes, 1 amb Claude. Claude encara no ha arrencat a «B2»"),
                "\(sortida.text)")
        #expect(o.urls.count == 1)
        #expect(o.fitxersEnObrir.count == 1 && o.fitxersEnObrir[0].hasPrefix("warp-launch-"))
        #expect(o.fitxersWarp.isEmpty, "el fitxer temporal s'esborra")
        let estat = try MagatzemEstat(carpeta: carpeta).carrega()
        let llancament = try #require(estat.llancaments.last)
        #expect(llancament.estat == .confirmat && llancament.esborrat)
        #expect(llancament.pestanyes == [uuid(3), uuid(4)])
        #expect(estat.pestanyes[uuid(3)]?.pane == uuidDeProva("d"))
        #expect(estat.pestanyes[uuid(4)]?.pane == uuidDeProva("e"))
        #expect(FileManager.default.fileExists(atPath: EntornClaude.ruta(carpeta: carpeta)))
    }

    /// Amb l'app oberta no obre res, ni escriu res: tots dos escriurien `estat.json`.
    @Test func ambLAppObertaNoObreRes() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        o.appOberta = true
        let estat = try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer))
        let (codi, sortida) = await o.executa(e, "obre", "1", "--obre", "--config", carpeta.path)
        #expect(codi == 1)
        #expect(sortida.errors.contains("l'app Warp Launch és oberta"))
        #expect(o.urls.isEmpty && o.engegades == 0 && o.fitxersWarp.isEmpty)
        #expect(try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer)) == estat)
    }

    /// Res per obrir: no escriu ni obre res, i codi 0.
    @Test func senseResPerObrir() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        let (codi, sortida) = await o.executa(e, "obre", "Oberta", "--obre", "--config", carpeta.path)
        #expect(codi == 0, "\(sortida.errors)")
        #expect(sortida.text.hasSuffix("Totes les pestanyes ja són obertes: no s'ha obert res.\n"))
        #expect(o.urls.isEmpty && o.fitxersWarp.isEmpty)
    }

    /// Si Warp és tancat, l'obre; si no pot, no escriu res.
    @Test func siNoPotObrirWarpNoEscriuRes() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        o.fallaEngegar = true
        var entorn = e.entorn
        var processos = ProcessosFalsos.ambWarp()
        processos.processos[40] = nil
        entorn.lector.processos = processos
        let rellotge = o.rellotge
        entorn.ara = { rellotge.ara }
        let estat = try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer))
        var sortida = Sortida()
        let codi = await OrdreCLI.executa(["obre", "1", "--obre", "--config", carpeta.path], entorn: entorn,
                                          obridor: o.obridor, sortida: &sortida)
        #expect(codi == 1)
        #expect(o.mostrat.contains("Warp és tancat: l'obro"))
        #expect(sortida.errors.contains("no s'ha pogut obrir Warp: macOS no l'obre"), "\(sortida.errors)")
        #expect(o.engegades == 1 && o.urls.isEmpty && o.fitxersWarp.isEmpty)
        #expect(try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer)) == estat)
    }

    /// D-P12: amb Warp Preview obert i Warp Stable tancat, `--obre` no obre Warp Stable, ni escriu res: ho diu.
    @Test func ambWarpPreviewNoObreRes() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        var entorn = try e.ambPreview()
        let rellotge = o.rellotge
        entorn.ara = { rellotge.ara }
        let estat = try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer))
        var sortida = Sortida()
        let codi = await OrdreCLI.executa(["obre", "1", "--obre", "--config", carpeta.path], entorn: entorn,
                                          obridor: o.obridor, sortida: &sortida)
        #expect(codi == 1)
        #expect(sortida.errors == "warp-launch: \(WarpPreview.obert.text) No s'ha obert res.\n", "\(sortida.errors)")
        #expect(o.mostrat.isEmpty && o.engegades == 0 && o.urls.isEmpty && o.fitxersWarp.isEmpty)
        #expect(try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer)) == estat)
    }

    /// 0.31.1: sense cap Warp, `--obre` no intenta obrir-lo, ni escriu res: ho diu.
    @Test func senseCapWarpNoObreRes() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        var entorn = try e.senseWarp()
        let rellotge = o.rellotge
        entorn.ara = { rellotge.ara }
        let estat = try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer))
        var sortida = Sortida()
        let codi = await OrdreCLI.executa(["obre", "1", "--obre", "--config", carpeta.path], entorn: entorn,
                                          obridor: o.obridor, sortida: &sortida)
        #expect(codi == 1)
        #expect(sortida.errors == "warp-launch: \(WarpPreview.capWarp.text) No s'ha obert res.\n", "\(sortida.errors)")
        #expect(o.mostrat.isEmpty && o.engegades == 0 && o.urls.isEmpty && o.fitxersWarp.isEmpty)
        #expect(try Data(contentsOf: carpeta.appending(path: EstatApp.nomFitxer)) == estat)
    }

    /// Amb `--obre`, el pla surt sempre de Warp i de Claude de debò: ni `--json`, ni una base o unes sessions de prova.
    @Test func obreNomesAdmetConfig() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        for (opcio, valor) in [("--json", nil), ("--warp", e.tmp.url("warp.sqlite").path), ("--sessions", e.tmp.url("sessions").path)] {
            let args = ["obre", "1", "--obre", "--config", carpeta.path, opcio] + (valor.map { [$0] } ?? [])
            var entorn = e.entorn
            entorn.ara = { Date(timeIntervalSince1970: 1_793_750_400) }
            var sortida = Sortida()
            let codi = await OrdreCLI.executa(args, entorn: entorn, obridor: o.obridor, sortida: &sortida)
            #expect(codi == 64)
            #expect(sortida.errors.contains("opció desconeguda per a obre --obre: «\(opcio)»"), "\(sortida.errors)")
        }
        #expect(o.urls.isEmpty && o.fitxersWarp.isEmpty)
    }

    /// Ctrl-C mentre Warp obre: el fitxer temporal s'esborra i el llançament queda desat, sense confirmar.
    @Test func ctrlCEsborraElFitxer() async throws {
        let e = try Escenari()
        let carpeta = try configuracio(e)
        let o = try ObridorFals(e)
        var abans: [String] = []
        var despres: [String]?
        var desat: Llancament?
        o.mentreObre = { [unowned o] in
            abans = o.fitxersWarp
            o.interrupcio?()
            despres = o.fitxersWarp
            desat = try MagatzemEstat(carpeta: carpeta).carrega().llancaments.last
        }
        _ = await o.executa(e, "obre", "Feina", "--obre", "--config", carpeta.path)
        #expect(abans.count == 1)
        #expect(despres == [])
        #expect(desat?.esborrat == true)
        #expect(desat?.estat == .senseConfirmar)
    }
}
