import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// Els lligams de les pestanyes a l'app (fase 3.1, 0.17.0): quan s'escriu `estat.json`, i l'ordre que es mostra i es
// copia amb la conversa de cada pestanya (D15). Sempre en carpetes temporals.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let pane = String(repeating: "a", count: 32)

private final class Carpeta {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var estat: URL { url.appending(path: EstatApp.nomFitxer) }
}

private let configuracio = Configuracio(plantilla: .habituals, finestres: [
    Finestra(id: id(100), nom: "a", pestanyes: [Pestanya(id: id(1), titol: "T1", carpeta: "/x", claude: .habituals)]),
])

/// La pestanya T1 al pane «a», amb la sessió `sessio` viva.
private func lectura(_ sessio: String) -> LecturaWarp {
    LecturaWarp(finestres: [], sessionsSensePestanya: [
        SessioClaude(pid: 10, sessionId: sessio, carpeta: "/x", ordre: ["claude"], opcions: OpcionsClaude(),
                     paneUUID: pane, dinsDeWarp: true),
    ], avisos: [])
}

@MainActor
@Suite struct EstatSessionsTests {
    /// La carpeta de Warp es queda a la memòria (no a `estat.json`): sobreviu a les lectures de cada minut, sense finestres, i
    /// una foto nova la canvia. Després d'un reinici, només queda el que diu `carpetaSessio`.
    @Test func recordaLaCarpetaDeWarpNomesAMemoria() throws {
        let carpeta = try Carpeta()
        let id = id(1)
        let pestanya = Pestanya(id: id, titol: "T", carpeta: "/x/b", claude: .habituals)
        let configuracio = Configuracio(plantilla: .habituals, finestres: [Finestra(id: UUID(), nom: "f", pestanyes: [pestanya])])
        let rellotge = { Date(timeIntervalSince1970: 1_793_750_400) }
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url), rellotge: rellotge)
        sessions.carrega()
        var canvis = 0
        sessions.enCanviar = { canvis += 1 }
        sessions.vincula([id: VincleImportat(pane: pane, sessio: "s", carpetaSessio: "/x/b", carpetaWarp: "/x/a")])
        #expect(canvis >= 1)
        func avis() -> Avis? { sessions.avisCarpeta(pestanya, inici: "/Users/prova", carpetaExisteix: { _ in true }) }
        #expect(avis()?.tipus == .carpetesDiferents(warp: "/x/a", claude: "/x/b", actual: "/x/b"))

        // La de cada minut no porta les finestres: no l'oblida.
        sessions.actualitza(amb: LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []), configuracio: configuracio)
        #expect(avis() != nil)
        #expect(!(try String(contentsOf: carpeta.url.appending(path: EstatApp.nomFitxer), encoding: .utf8)).contains("carpetaWarp"))

        // Una foto nova on ja coincideixen.
        let claude = SessioClaude(pid: 1, sessionId: "s", carpeta: "/x/b", iniciada: nil, ordre: ["claude"], opcions: OpcionsClaude(),
                                  paneUUID: pane, dinsDeWarp: true)
        sessions.actualitza(amb: LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "T", color: nil, panes: [
                PaneLlegit(uuid: pane, carpeta: "/x/b", origenCarpeta: .pane, carpetaExisteix: true, claude: claude),
            ]),
        ])], sessionsSensePestanya: [], avisos: []), configuracio: configuracio)
        #expect(avis() == nil)

        // Importada amb l'última carpeta de Claude diferent, després de reiniciar l'app.
        let reiniciada = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url), rellotge: rellotge)
        reiniciada.carrega()
        var aA = pestanya
        aA.carpeta = "/x/a"
        #expect(reiniciada.avisCarpeta(aA, inici: "/Users/prova", carpetaExisteix: { _ in true })?.tipus
            == .carpetesDiferents(warp: nil, claude: "/x/b", actual: "/x/a"))
        #expect(reiniciada.avisCarpeta(pestanya, inici: "/Users/prova", carpetaExisteix: { _ in true }) == nil, "la foto no es desa")
    }

    /// Una foto on Claude ja no és viu (Warp tancat, o Claude ha sortit) i Warp diu el mateix no treu l'avís: la pestanya
    /// continua a la carpeta triada. Si Warp ja diu una altra cosa, sí.
    @Test func laFotoSenseClaudeNoTreuLAvis() throws {
        let carpeta = try Carpeta()
        let id = id(1)
        let pestanya = Pestanya(id: id, titol: "T", carpeta: "/x/b", claude: .habituals)
        let configuracio = Configuracio(plantilla: .habituals, finestres: [Finestra(id: UUID(), nom: "f", pestanyes: [pestanya])])
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url), rellotge: { Date(timeIntervalSince1970: 1_793_750_400) })
        sessions.carrega()
        sessions.vincula([id: VincleImportat(pane: pane, sessio: "s", carpetaSessio: "/x/b", carpetaWarp: "/x/a")])
        func foto(_ carpetaPane: String) -> LecturaWarp {
            LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
                PestanyaLlegida(posicio: 0, titol: "T", color: nil, panes: [
                    PaneLlegit(uuid: pane, carpeta: carpetaPane, origenCarpeta: .pane, carpetaExisteix: true),
                ]),
            ])], sessionsSensePestanya: [], avisos: [])
        }
        func avis() -> Avis? { sessions.avisCarpeta(pestanya, inici: "/Users/prova", carpetaExisteix: { _ in true }) }
        sessions.actualitza(amb: foto("/x/a"), configuracio: configuracio)
        #expect(avis()?.tipus == .carpetesDiferents(warp: "/x/a", claude: "/x/b", actual: "/x/b"))
        sessions.actualitza(amb: foto("/x/b"), configuracio: configuracio)
        #expect(avis() == nil, "ara Warp diu la mateixa")
    }

    /// Només s'escriu si alguna cosa canvia.
    @Test func nomesEsDesaSiCanvia() throws {
        let carpeta = try Carpeta()
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url), rellotge: { Date(timeIntervalSince1970: 1_793_750_400) })
        sessions.carrega()
        #expect(sessions.bloqueig == nil)
        sessions.actualitza(amb: lectura("s1"), configuracio: configuracio)
        #expect(!FileManager.default.fileExists(atPath: carpeta.estat.path), "sense lligam, la sessió no és de cap pestanya")

        sessions.vincula([id(1): VincleImportat(pane: pane)])
        #expect(FileManager.default.fileExists(atPath: carpeta.estat.path))
        sessions.actualitza(amb: lectura("s1"), configuracio: configuracio)
        #expect(sessions.conversa(de: id(1)) == "s1")
        #expect(try MagatzemEstat(carpeta: carpeta.url).carrega().conversa(de: id(1)) == "s1")

        // La mateixa lectura: no s'escriu (si s'escrivís, el fitxer tornaria a existir).
        try FileManager.default.removeItem(at: carpeta.estat)
        sessions.actualitza(amb: lectura("s1"), configuracio: configuracio)
        #expect(!FileManager.default.fileExists(atPath: carpeta.estat.path))
        // Un `/clear`: sí.
        sessions.actualitza(amb: lectura("s2"), configuracio: configuracio)
        #expect(try MagatzemEstat(carpeta: carpeta.url).carrega().conversa(de: id(1)) == "s2")
    }

    /// Sense carpeta (arguments incorrectes), ni es llegeix ni s'escriu.
    @Test func senseMagatzemNoFaRes() {
        let sessions = EstatSessions(magatzem: nil)
        sessions.carrega()
        sessions.vincula([id(1): VincleImportat(pane: pane, sessio: "s1")])
        #expect(sessions.conversa(de: id(1)) == nil)
    }

    /// D'una versió més nova: no s'hi escriu mai, i es diu per què.
    @Test func unaVersioMesNovaBloqueja() throws {
        let carpeta = try Carpeta()
        let text = Data(#"{"versio": 9}"#.utf8)
        try text.write(to: carpeta.estat)
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url))
        sessions.carrega()
        #expect(sessions.bloqueig?.contains("versió 9") == true)
        sessions.vincula([id(1): VincleImportat(pane: pane, sessio: "s1")])
        #expect(try Data(contentsOf: carpeta.estat) == text)
    }

    /// Un llançament nou que no s'ha pogut desar no queda a la memòria: no s'ha obert res, i no ha d'avisar de res. Un
    /// de conegut sí que s'hi queda, i es desarà després (revisió de la 0.20.0).
    @Test func unLlancamentQueNoEsPotDesar() throws {
        let carpeta = try Carpeta()
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url))
        sessions.carrega()
        let llancament = Llancament(id: id(500), fitxer: "f", mida: 1, creat: Date(timeIntervalSince1970: 1_793_750_400),
                                    finestra: id(100), pestanyes: [id(1)], estat: .pendent)
        #expect(sessions.desa(llancament: llancament) == nil)
        // La carpeta, només de lectura: no s'hi pot escriure.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: carpeta.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: carpeta.url.path) }
        var nou = llancament
        nou.id = id(501)
        #expect(sessions.desa(llancament: nou) != nil)
        #expect(sessions.estat.llancaments.map(\.id) == [id(500)])
        var confirmat = llancament
        confirmat.estat = .confirmat
        #expect(sessions.desa(llancament: confirmat) != nil)
        #expect(sessions.estat.llancaments.map(\.estat) == [.confirmat])
    }

    /// D15: «Copia l'ordre» porta la conversa de la pestanya, si se sap; si no, cap (una de nova). Mai `--continue`.
    @Test func lOrdreCopiadaPortaLaConversa() throws {
        let carpeta = try Carpeta()
        let magatzem = MagatzemConfiguracio(carpeta: carpeta.url, inici: "/Users/prova")
        try magatzem.desa(configuracio, sobre: nil)
        let editor = Editor(magatzem: magatzem, retardDesat: nil)
        editor.carrega()
        #expect(editor.ordres([id(1)]) == "claude --dangerously-skip-permissions --effort ultracode")
        editor.conversaDe = { $0.id == id(1) ? "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d" : nil }
        #expect(editor.ordres([id(1)])
            == "claude --dangerously-skip-permissions --effort ultracode --resume 1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d")
    }

    /// L'inspector i «Copia l'ordre»: la conversa més recent de la carpeta, com el full (D7).
    @Test func laConversaAReprendreSurtDelDisc() throws {
        let carpeta = try Carpeta()
        let projecte = carpeta.url.appending(path: "projects/-x-t1")
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8).write(to: projecte.appending(path: conversa + ".jsonl"))
        let sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta.url))
        sessions.carrega()
        let transcripcions = LectorTranscripcions(carpeta: carpeta.url.appending(path: "projects"))
        let pestanya = Pestanya(id: id(1), titol: "T", carpeta: "/x/t1", claude: .habituals)
        #expect(sessions.conversaAReprendre(pestanya, transcripcions: transcripcions) == conversa)
        var altra = pestanya
        altra.carpeta = "/x/altra"
        #expect(sessions.conversaAReprendre(altra, transcripcions: transcripcions) == nil)

        // No torna a llegir el disc fins a la pròxima lectura de Warp: l'inspector ho demana a cada redibuix.
        try FileManager.default.removeItem(at: projecte.appending(path: conversa + ".jsonl"))
        #expect(sessions.conversaAReprendre(pestanya, transcripcions: transcripcions) == conversa)
        sessions.actualitza(amb: LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: []), configuracio: configuracio)
        #expect(sessions.conversaAReprendre(pestanya, transcripcions: transcripcions) == nil)
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8)
            .write(to: projecte.appending(path: conversa + ".jsonl"))

        // Si l'última lectura de Warp diu que és viva en un altre lloc, no s'ofereix.
        var ambFeina = LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: [])
        ambFeina.sessionsNoInteractives = [SessioViva(pid: 9, sessionId: conversa, tipus: "bg", carpeta: "/x/t1")]
        sessions.actualitza(amb: ambFeina, configuracio: configuracio)
        #expect(sessions.conversaAReprendre(pestanya, transcripcions: transcripcions) == nil)
    }

    /// Crear la configuració des de Warp passa els lligams a l'app, un cop desada.
    @Test func crearPassaElsLligams() throws {
        let carpeta = try Carpeta()
        let editor = Editor(magatzem: MagatzemConfiguracio(carpeta: carpeta.url, inici: "/Users/prova"), retardDesat: nil)
        editor.carrega()
        var rebuts: [UUID: VincleImportat]?
        editor.enImportar = { rebuts = $0.vincles }
        let vincles = [id(1): VincleImportat(pane: pane, sessio: "s1")]
        editor.crea(amb: Importacio(configuracio: configuracio, origens: [:], notes: [], vincles: vincles))
        #expect(rebuts == vincles)
        #expect(FileManager.default.fileExists(atPath: carpeta.url.appending(path: MagatzemConfiguracio.nomFitxer).path))
    }

    /// Cada lectura bona de Warp avisa l'app (que hi posa al dia els lligams); una que falla, no.
    @Test func cadaLecturaAvisa() async {
        var avisos = 0
        let warp = EstatWarp(lector: { lectura("s1") })
        warp.enLlegir = { _ in avisos += 1 }
        await warp.llegeix()
        await warp.llegeix()
        #expect(avisos == 2)
        struct Falla: Error {}
        let trencat = EstatWarp(lector: { throw Falla() })
        trencat.enLlegir = { _ in avisos += 1 }
        await trencat.llegeix()
        #expect(avisos == 2)
    }
}
