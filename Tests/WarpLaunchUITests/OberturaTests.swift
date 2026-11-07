import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// Obrir una finestra a Warp (fase 3.1, 0.20.0), amb un obridor fals: no s'obre res. Les lectures de Warp són
// inventades, el rellotge el mou la prova i la «carpeta de Warp» és una de temporal.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
private func pane(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }

/// «W»: T1 amb Claude (sense conversa coneguda) i T2 només terminal; i «Buida», sense pestanyes.
private let configuracio = Configuracio(plantilla: .habituals, finestres: [
    Finestra(id: id(100), nom: "W", pestanyes: [
        Pestanya(id: id(1), titol: "T1", carpeta: "/x/t1", claude: .habituals),
        Pestanya(id: id(2), titol: "T2", carpeta: "/x/t2", claude: ClaudePestanya(activat: false)),
    ]),
    Finestra(id: id(200), nom: "Buida"),
])

private struct Llegida {
    var titol: String?
    var pane: String
    var carpeta: String
    var claude: SessioClaude?
}

private func lectura(_ finestres: [[Llegida]], warpObert: Bool = true) -> LecturaWarp {
    var lectura = LecturaWarp(finestres: finestres.enumerated().map { n, pestanyes in
        FinestraLlegida(numero: n + 1, pestanyaActiva: 0, pestanyes: pestanyes.enumerated().map { posicio, p in
            PestanyaLlegida(posicio: posicio, titol: p.titol, color: nil, panes: [
                PaneLlegit(uuid: p.pane, carpeta: p.carpeta, origenCarpeta: .pane, carpetaExisteix: true, claude: p.claude),
            ])
        })
    }, sessionsSensePestanya: [], avisos: [])
    lectura.warpObert = warpObert
    return lectura
}

/// Warp abans d'obrir: una finestra que no té res a veure.
private let abans = lectura([[Llegida(titol: "Altra", pane: pane("a"), carpeta: "/x/altra")]])

/// Warp amb la restauració de sessió desactivada: sense finestres, amb els terminals i les sessions.
private func senseBase(_ terminals: [TerminalViu], sessions: [SessioClaude] = [], warpObert: Bool = true) -> LecturaWarp {
    LecturaWarp(finestres: [], sessionsSensePestanya: sessions, avisos: [], warpObert: warpObert, terminals: terminals,
                warpDesaFinestres: false)
}

/// Els terminals de la finestra nova: el de T1, amb la marca del seu Claude, i el de T2, només terminal.
private let terminalsNous = [TerminalViu(pid: 601, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true),
                             TerminalViu(pid: 602, carpeta: "/x/t2")]

/// El Claude de T1, amb la seva marca, al pane «n».
private func claudeT1(pane panell: String = pane("n")) -> SessioClaude {
    SessioClaude(pid: 77, sessionId: "s-nova", carpeta: "/x/t1", iniciada: t0 + 1, ordre: ["claude"],
                 opcions: OpcionsClaude(), paneUUID: panell, dinsDeWarp: true, marca: id(1))
}

/// Warp després d'obrir: la finestra nova, amb el Claude de T1 (marca) en marxa.
private let despres = lectura([
    [Llegida(titol: "Altra", pane: pane("a"), carpeta: "/x/altra")],
    [Llegida(titol: "T1", pane: pane("n"), carpeta: "/x/t1", claude: claudeT1()),
     Llegida(titol: "T2", pane: pane("m"), carpeta: "/x/t2")],
])

/// La finestra nova, però el Claude de T1 encara no ha arrencat.
private let despresSenseClaude = lectura([
    [Llegida(titol: "Altra", pane: pane("a"), carpeta: "/x/altra")],
    [Llegida(titol: "T1", pane: pane("n"), carpeta: "/x/t1"), Llegida(titol: "T2", pane: pane("m"), carpeta: "/x/t2")],
])

/// El Claude de T1 ja ha escrit la seva sessió, però Warp encara no ha desat la finestra nova.
private let nomesLaMarca: LecturaWarp = {
    var lectura = abans
    lectura.sessionsSensePestanya = [claudeT1()]
    return lectura
}()

@MainActor
private final class Banc {
    let carpeta: URL
    let warp: FitxersLaunchWarp
    let editor: Editor
    let sessions: EstatSessions
    var obertura: Obertura!
    /// Les lectures que tornarà Warp, en ordre; l'última es repeteix.
    var lectures: [LecturaWarp] = [abans]
    var llegides = 0
    var ara = t0
    var urls: [URLLlancament] = []
    var fallaObrir: (any Error)?
    /// Els ids que dona `nouId`: 500, 501…
    var seguentId = 500
    /// Falla només en obrir l'URL d'aquest llançament.
    var fallaObrirLlancament: UUID?
    /// Quantes vegades s'ha demanat obrir Warp, i si falla.
    var engegades = 0
    var fallaEngegar: (any Error)?
    /// `openApplication` no torna (per exemple, un diàleg del sistema).
    var engegarNoTorna = false
    /// Quantes URL s'havien demanat quan s'ha obert Warp.
    var urlsEnEngegar: Int?
    /// El que hi havia a la «carpeta de Warp» i a `estat.json` quan s'ha demanat obrir.
    var enObrir: (fitxers: [String], llancament: Llancament?)?
    /// Quants fitxers hi havia a la «carpeta de Warp» a cada lectura.
    var fitxersEnLlegir: [Int] = []
    /// Es crida mentre «Warp» obre (per exemple, per sortir de l'app a mig obrir).
    var mentreObre: (() -> Void)?
    /// Es crida abans de cada lectura, amb el seu número (0…).
    var abansDeLlegir: ((Int) -> Void)?

    init(estat: Data? = nil, configuracio: Configuracio = configuracio) throws {
        carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: carpeta.appending(path: "warp"), withIntermediateDirectories: true)
        let config = carpeta.appending(path: "config")
        try MagatzemConfiguracio(carpeta: config, inici: "/Users/prova").desa(configuracio, sobre: nil)
        if let estat { try estat.write(to: config.appending(path: EstatApp.nomFitxer)) }
        warp = FitxersLaunchWarp(carpeta: carpeta.appending(path: "warp"))
        editor = Editor(magatzem: MagatzemConfiguracio(carpeta: config, inici: "/Users/prova"), retardDesat: nil)
        editor.carrega()
        let rellotge = Rellotge()
        sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: config), rellotge: { rellotge.ara })
        sessions.carrega()
        obertura = Obertura(editor: editor, sessions: sessions, entorn: Obertura.Entorn(
            llegeix: { [unowned self] in
                abansDeLlegir?(llegides)
                let lectura = lectures[min(llegides, lectures.count - 1)]
                llegides += 1
                fitxersEnLlegir.append(fitxersWarp.count)
                // Com `EstatWarp.enLlegir` a l'app: cada lectura posa al dia els lligams.
                sessions.actualitza(amb: lectura, configuracio: editor.configuracio)
                obertura.enLlegir(lectura)
                return .success(lectura)
            },
            obre: { [unowned self] url in
                let noms = (try? FileManager.default.contentsOfDirectory(atPath: warp.carpeta.path)) ?? []
                enObrir = (noms, sessions.estat.llancaments.last)
                urls.append(url)
                mentreObre?()
                if let fallaObrir { throw fallaObrir }
                if let fallaObrirLlancament, url.url.absoluteString.hasSuffix(fallaObrirLlancament.uuidString.lowercased()) {
                    throw NoObre()
                }
            },
            engegaWarp: { [unowned self] in
                engegades += 1
                urlsEnEngegar = urls.count
                if let fallaEngegar { throw fallaEngegar }
                if engegarNoTorna { try await Task.sleep(for: .seconds(3600)) }
            },
            fitxers: warp,
            transcripcions: LectorTranscripcions(carpeta: carpeta.appending(path: "projects")),
            confianca: LectorConfianca(ruta: carpeta.appending(path: "claude.json")),
            versioWarp: { "0.2026.10.21" },
            inici: "/Users/prova",
            carpetaExisteix: { _ in true },
            nouId: { [unowned self] in
                defer { seguentId += 1 }
                return id(seguentId)
            },
            rellotge: { [unowned self] in ara },
            espera: { [unowned self] durada in
                ara += Double(durada.components.seconds) + Double(durada.components.attoseconds) / 1e18
                rellotge.ara = ara
            }))
        editor.obertura = obertura
    }

    deinit { try? FileManager.default.removeItem(at: carpeta) }

    var fitxersWarp: [String] { (try? FileManager.default.contentsOfDirectory(atPath: warp.carpeta.path)) ?? [] }
    var estatAlDisc: EstatApp { (try? MagatzemEstat(carpeta: carpeta.appending(path: "config")).carrega()) ?? EstatApp() }

    var proposta: Obertura.Proposta? {
        if case let .confirmant(proposta) = obertura.estat { proposta } else { nil }
    }
}

private final class Rellotge: @unchecked Sendable {
    var ara = t0
}

private struct NoObre: Error, CustomStringConvertible {
    var description: String { "Warp no respon" }
}

@MainActor
@Suite struct OberturaTests {
    /// Les pestanyes en bypass porten l'entorn de Claude, que s'escriu abans d'obrir; un terminal, no.
    @Test func lEntornDeClaudeSEscriuAbansDObrir() async throws {
        let b = try Banc()
        let config = b.carpeta.appending(path: "config")
        let ruta = EntornClaude.ruta(carpeta: config)
        await b.obertura.demana(id(100))
        let proposta = try #require(b.proposta)
        let linies = proposta.pla.aObrir.map(\.yaml.exec)
        #expect(linies[0]?.contains("\(EntornClaude.variable)=\(ruta) ") == true)
        #expect(linies[1] == nil, "T2 només és un terminal")
        #expect(!FileManager.default.fileExists(atPath: ruta), "el full no escriu res")

        var alObrir: Data?
        b.mentreObre = { alObrir = try? Data(contentsOf: URL(filePath: ruta)) }
        b.lectures = [abans, abans, abans, despres]
        await b.obertura.confirmaIObre()
        #expect(alObrir == Data(EntornClaude.text.utf8))
        #expect(b.urls.count == 1)
    }

    /// Sense poder escriure l'entorn, no obre res: quedaria una feina en `auto` sense que ningú ho sabés.
    @Test func siNoPotEscriureLEntornNoObre() async throws {
        let b = try Banc()
        let ruta = EntornClaude.ruta(carpeta: b.carpeta.appending(path: "config"))
        try FileManager.default.createDirectory(atPath: ruta, withIntermediateDirectories: true)
        await b.obertura.demana(id(100))
        b.lectures = [abans, abans, abans, despres]
        await b.obertura.confirmaIObre()
        #expect(b.urls.isEmpty)
        #expect(b.fitxersWarp.isEmpty)
        #expect(b.obertura.resultat?.correcte == false)
        #expect(b.estatAlDisc.llancaments.last?.estat == .error)
    }

    /// Una finestra sense cap pestanya en bypass ni el porta ni l'escriu.
    @Test func senseBypassNoHiHaEntorn() async throws {
        let b = try Banc(configuracio: Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(100), nom: "W", pestanyes: [
                Pestanya(id: id(1), titol: "T1", carpeta: "/x/t1", claude: ClaudePestanya(esforc: "high")),
                Pestanya(id: id(2), titol: "T2", carpeta: "/x/t2", claude: ClaudePestanya(activat: false)),
            ]),
        ]))
        let ruta = EntornClaude.ruta(carpeta: b.carpeta.appending(path: "config"))
        await b.obertura.demana(id(100))
        let proposta = try #require(b.proposta)
        #expect(!proposta.pla.necessitaEntornClaude)
        #expect(proposta.pla.aObrir[0].yaml.exec?.contains(EntornClaude.variable) == false)
        b.lectures = [abans, abans, abans, despres]
        await b.obertura.confirmaIObre()
        #expect(b.urls.count == 1)
        #expect(!FileManager.default.fileExists(atPath: ruta))
    }

    /// El camí bo: el full, el fitxer escrit abans d'obrir i amb el llançament ja desat, la finestra nova vista, el
    /// fitxer esborrat, i el pane i la conversa de cada pestanya a `estat.json`.
    @Test func obreIConfirma() async throws {
        let b = try Banc()
        #expect(b.obertura.potObrir(id(100)))
        #expect(!b.obertura.potObrir(id(200)), "sense pestanyes")
        #expect(!b.obertura.potObrir(nil))

        await b.obertura.demana(id(100))
        let proposta = try #require(b.proposta)
        #expect(proposta.pla.aObrir.map(\.pestanya.id) == [id(1), id(2)])
        #expect(proposta.versioWarp == "0.2026.10.21")
        let fitxer = try #require(try proposta.fitxer?.get())
        #expect(fitxer.nomFitxer == "warp-launch-00000000-0000-0000-0000-000000000500.yaml")
        #expect(b.fitxersWarp.isEmpty && b.urls.isEmpty, "el full no escriu ni obre res")
        #expect(!b.obertura.potObrir(id(100)), "una sola alhora")

        // La comprovació i la primera espera encara veuen el Warp d'abans; la segona, la finestra nova.
        b.lectures = [abans, abans, abans, despres]
        await b.obertura.confirmaIObre()
        #expect(b.urls.map(\.url.absoluteString) == ["warp://launch/warp-launch-00000000-0000-0000-0000-000000000500"])
        #expect(b.enObrir?.fitxers == [fitxer.nomFitxer])
        #expect(b.enObrir?.llancament?.estat == .pendent)
        #expect(b.fitxersWarp.isEmpty, "esborrat en confirmar")
        #expect(b.obertura.estat == .cap)
        #expect(b.obertura.resultat == Obertura.Resultat(correcte: true, text: "S'ha obert «W» a Warp: 2 pestanyes, 1 amb Claude."))

        let estat = b.estatAlDisc
        let llancament = try #require(estat.llancaments.last)
        #expect(llancament.id == id(500) && llancament.estat == .confirmat && llancament.esborrat)
        #expect(llancament.segons == 1.0 && llancament.mida == fitxer.mida && llancament.pestanyes == [id(1), id(2)])
        #expect(estat.pestanyes[id(1)]?.pane == pane("n") && estat.pestanyes[id(1)]?.sessio == "s-nova")
        #expect(estat.pestanyes[id(2)]?.pane == pane("m") && estat.pestanyes[id(2)]?.origen == .llancament)

        // Tornar-la a obrir: ja és oberta.
        b.obertura.descartaResultat()
        await b.obertura.demana(id(100))
        #expect(b.proposta?.pla.aObrir.isEmpty == true)
        #expect(b.proposta?.pla.obertes.count == 2)
        await b.obertura.confirmaIObre()
        #expect(b.urls.count == 1, "no hi ha res per obrir")
    }

    // MARK: Warp tancat (0.22.0)

    /// Warp és tancat: el full ho diu, i només el botó l'obre. Demanar el full no obre res, tampoc Warp.
    @Test func ambWarpTancatElFullHoDiu() async throws {
        let b = try Banc()
        b.lectures = [senseBase([], warpObert: false)]
        await b.obertura.demana(id(100))
        let proposta = try #require(b.proposta)
        #expect(proposta.warpTancat && !proposta.warpDesaFinestres)
        #expect(proposta.pla.aObrir.count == 2)
        #expect(b.engegades == 0 && b.urls.isEmpty && b.fitxersWarp.isEmpty && b.estatAlDisc.llancaments.isEmpty)
        b.obertura.cancela()
        #expect(b.obertura.estat == .cap && b.engegades == 0)
    }

    /// «Obre» amb Warp tancat: primer obre Warp, n'espera l'arrencada, ho torna a comprovar i després obre la finestra, un sol
    /// cop. El bàner avisa de la finestra buida que obre Warp en arrencar.
    @Test func ambWarpTancatLObreIDespresObreLaFinestra() async throws {
        let b = try Banc()
        b.lectures = [senseBase([], warpObert: false)]
        await b.obertura.demana(id(100))
        b.llegides = 0
        // La comprovació i la primera espera: encara tancat. Després, obert, amb el terminal de la finestra buida (a l'inici),
        // i finalment, els dos terminals de la finestra.
        let buida = TerminalViu(pid: 500, carpeta: "/Users/prova")
        b.lectures = [senseBase([], warpObert: false), senseBase([], warpObert: false), senseBase([buida]), senseBase([buida]),
                      senseBase([buida] + terminalsNous, sessions: [claudeT1()])]
        await b.obertura.confirmaIObre()
        #expect(b.engegades == 1)
        #expect(b.urlsEnEngegar == 0, "primer Warp, i després la finestra")
        #expect(b.urls.count == 1)
        #expect(b.estatAlDisc.llancaments.last?.estat == .confirmat)
        let resultat = try #require(b.obertura.resultat)
        #expect(resultat.correcte)
        #expect(resultat.text == "S'ha obert «W» a Warp: 2 pestanyes, 1 amb Claude. "
            + "En arrencar, Warp ha obert també una finestra buida: la pots tancar.")
    }

    /// Si Warp restaura la sessió, no hi ha finestra buida, i no se'n parla.
    @Test func siWarpRestauraNoParlaDeLaFinestraBuida() async throws {
        let b = try Banc()
        b.lectures = [lectura([], warpObert: false)]
        await b.obertura.demana(id(100))
        #expect(b.proposta?.warpDesaFinestres == true)
        b.llegides = 0
        b.lectures = [lectura([], warpObert: false), lectura([]), lectura([]), despres]
        await b.obertura.confirmaIObre()
        #expect(b.engegades == 1 && b.urls.count == 1)
        #expect(b.obertura.resultat?.text == "S'ha obert «W» a Warp: 2 pestanyes, 1 amb Claude.")
    }

    /// Si en arrencar Warp ha restaurat alguna pestanya, el pla canvia: no s'obre res, i es torna al full. El segon «Obre» ja
    /// no obre Warp.
    @Test func siWarpRestauraPestanyesEsTornaAConfirmar() async throws {
        let b = try Banc()
        b.lectures = [lectura([], warpObert: false)]
        await b.obertura.demana(id(100))
        b.llegides = 0
        let ambT1 = lectura([[Llegida(titol: "T1", pane: pane("n"), carpeta: "/x/t1", claude: claudeT1())]])
        b.lectures = [lectura([], warpObert: false), ambT1]
        await b.obertura.confirmaIObre()
        let proposta = try #require(b.proposta)
        #expect(proposta.haCanviat && !proposta.warpTancat)
        #expect(proposta.pla.aObrir.map(\.pestanya.id) == [id(2)])
        #expect(b.engegades == 1 && b.urls.isEmpty && b.fitxersWarp.isEmpty)
    }

    /// El full reprèn la conversa més recent de la carpeta, llegida del disc (D7).
    @Test func elFullRepenLaConversaMesRecent() async throws {
        let b = try Banc()
        let projecte = b.carpeta.appending(path: "projects/-x-t1")
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8).write(to: projecte.appending(path: conversa + ".jsonl"))
        await b.obertura.demana(id(100))
        let pla = try #require(b.proposta?.pla)
        #expect(pla.aObrir.first?.conversa == .repren(conversa))
        #expect(pla.xifres.reprenen == 1)
    }

    /// Warp es tanca amb el full obert: no s'obre res, i el full torna dient-ho. El segon «Obre» sí que l'obre.
    @Test func siWarpEsTancaAmbElFullObertEsTornaAConfirmar() async throws {
        let b = try Banc()
        b.lectures = [senseBase([])]
        await b.obertura.demana(id(100))
        #expect(b.proposta?.warpTancat == false)
        b.llegides = 0
        b.lectures = [senseBase([], warpObert: false)]
        await b.obertura.confirmaIObre()
        let proposta = try #require(b.proposta)
        #expect(proposta.haCanviat && proposta.warpTancat)
        #expect(b.engegades == 0 && b.urls.isEmpty && b.fitxersWarp.isEmpty)
        await b.obertura.confirmaIObre()
        #expect(b.engegades == 1)
    }

    /// Warp és tancat, restaura la sessió i totes les pestanyes hi són: no són «ja obertes». Ho diu, i no obre res.
    @Test func siWarpTancatLesRestauraraNoDiuQueSonObertes() async throws {
        let b = try Banc()
        b.sessions.lliga(panes: [id(1): pane("a"), id(2): pane("b")])
        b.lectures = [lectura([[Llegida(titol: "T1", pane: pane("a"), carpeta: "/x/t1"),
                                Llegida(titol: "T2", pane: pane("b"), carpeta: "/x/t2")]], warpObert: false)]
        await b.obertura.demana(id(100))
        #expect(b.obertura.estat == .noEsPot("Warp és tancat, i en obrir-se restaurarà aquestes pestanyes, sense Claude. "
            + "Obre'l i torna-ho a provar."))
        #expect(b.engegades == 0 && b.urls.isEmpty)
    }

    /// Si `openApplication` no torna, el full no es queda blocat: el límit és el dels 30 s.
    @Test func siObrirWarpNoTornaElFullNoEsQueda() async throws {
        let b = try Banc()
        b.lectures = [senseBase([], warpObert: false)]
        b.engegarNoTorna = true
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.engegades == 1)
        #expect(b.obertura.estat == .noEsPot("Warp no ha arrencat en 30 s: mira'l i torna-ho a provar."))
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty)
    }

    /// Amb la restauració activada, els terminals no acaben l'espera: cal la finestra, que dona el pane de T2, sense Claude.
    /// Sense el pane, el pròxim «Obre» la tornaria a obrir.
    @Test func ambLaRestauracioActivadaEsperaLaFinestra() async throws {
        let b = try Banc()
        var senseFinestra = nomesLaMarca
        senseFinestra.terminals = terminalsNous
        b.lectures = [abans, abans, senseFinestra, despres]
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.estatAlDisc.llancaments.last?.estat == .confirmat)
        #expect(b.estatAlDisc.pestanyes[id(2)]?.pane == pane("m"))
    }

    /// Una pestanya de terminal a la carpeta d'inici: amb Warp obert, el seu terminal la confirma, sense els 30 s i el bàner
    /// d'error. Si l'app acaba d'engegar Warp, aquest terminal podria ser el de la finestra buida, i no es confirma.
    @Test func unaPestanyaALaCarpetaDInici() async throws {
        let aInici = Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(100), nom: "W", pestanyes: [
                Pestanya(id: id(1), titol: "T", carpeta: "/Users/prova", claude: ClaudePestanya(activat: false)),
            ]),
        ])
        let shell = TerminalViu(pid: 9, carpeta: "/Users/prova")

        let obert = try Banc(configuracio: aInici)
        obert.lectures = [senseBase([]), senseBase([]), senseBase([shell])]
        await obert.obertura.demana(id(100))
        await obert.obertura.confirmaIObre()
        #expect(obert.estatAlDisc.llancaments.last?.estat == .confirmat)
        #expect(obert.obertura.resultat?.correcte == true)

        let tancat = try Banc(configuracio: aInici)
        tancat.lectures = [senseBase([], warpObert: false)]
        await tancat.obertura.demana(id(100))
        tancat.llegides = 0
        tancat.lectures = [senseBase([], warpObert: false), senseBase([], warpObert: false), senseBase([]), senseBase([]),
                           senseBase([shell])]
        await tancat.obertura.confirmaIObre()
        #expect(tancat.urls.count == 1)
        #expect(tancat.estatAlDisc.llancaments.last?.estat == .senseConfirmar)
    }

    /// Si no es pot obrir Warp, o no arrenca en 30 s, no s'escriu cap fitxer ni es demana res.
    @Test func siWarpNoSObreNoObreRes() async throws {
        let b = try Banc()
        b.lectures = [senseBase([], warpObert: false)]
        b.fallaEngegar = NoObre()
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.obertura.estat == .noEsPot("No s'ha pogut obrir Warp: Warp no respon"))
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty && b.estatAlDisc.llancaments.isEmpty)
    }

    @Test func siWarpNoArrencaNoObreRes() async throws {
        let b = try Banc()
        b.lectures = [senseBase([], warpObert: false)]
        await b.obertura.demana(id(100))
        let inici = b.ara
        await b.obertura.confirmaIObre()
        #expect(b.obertura.estat == .noEsPot("Warp no ha arrencat en 30 s: mira'l i torna-ho a provar."))
        #expect(b.ara >= inici + 30)
        #expect(b.engegades == 1 && b.urls.isEmpty && b.fitxersWarp.isEmpty && b.estatAlDisc.llancaments.isEmpty)
    }

    /// Warp obert: «Obre» no el torna a obrir.
    @Test func ambWarpObertNoLObre() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        b.llegides = 0
        b.lectures = [abans, despres]
        await b.obertura.confirmaIObre()
        #expect(b.engegades == 0 && b.urls.count == 1)
    }

    // MARK: La restauració de sessió desactivada (0.22.0)

    /// El cas real de «Principal» (05/11/2026): Warp no desa les finestres, però cada pestanya té el seu terminal nou. Es
    /// confirma de seguida, i no als 30 s amb «No s'ha pogut reconèixer la finestra nova».
    @Test func senseFinestresEsConfirmaPelsTerminals() async throws {
        let b = try Banc()
        b.lectures = [senseBase([])]
        await b.obertura.demana(id(100))
        #expect(b.proposta?.warpDesaFinestres == false && b.proposta?.warpTancat == false)
        b.llegides = 0
        let inici = b.ara
        b.lectures = [senseBase([]), senseBase(terminalsNous, sessions: [claudeT1()])]
        await b.obertura.confirmaIObre()
        #expect(b.ara < inici + 2)
        let llancament = try #require(b.estatAlDisc.llancaments.last)
        #expect(llancament.estat == .confirmat && llancament.esborrat)
        #expect(b.fitxersWarp.isEmpty)
        #expect(b.estatAlDisc.pestanyes[id(1)]?.pane == pane("n"))
        #expect(b.estatAlDisc.pestanyes[id(1)]?.sessio == "s-nova")
        #expect(b.obertura.resultat == Obertura.Resultat(correcte: true, text: "S'ha obert «W» a Warp: 2 pestanyes, 1 amb Claude."))
    }

    /// Els terminals que ja hi eren no confirmen res, encara que siguin a la mateixa carpeta.
    @Test func elsTerminalsDAbansNoConfirmen() async throws {
        let b = try Banc()
        let vells = [TerminalViu(pid: 1, carpeta: "/x/t1"), TerminalViu(pid: 2, carpeta: "/x/t2")]
        b.lectures = [senseBase(vells)]
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.estatAlDisc.llancaments.last?.estat == .senseConfirmar)
        #expect(b.obertura.resultat?.correcte == false)
    }

    /// Un Claude que s'atura a preguntar: la finestra es confirma, i el bàner diu quin no ha arrencat.
    @Test func unClaudeAturatEsConfirmaIHoDiu() async throws {
        let b = try Banc()
        b.lectures = [senseBase([])]
        await b.obertura.demana(id(100))
        b.llegides = 0
        b.lectures = [senseBase([]), senseBase(terminalsNous)]
        await b.obertura.confirmaIObre()
        #expect(b.estatAlDisc.llancaments.last?.estat == .confirmat)
        #expect(b.estatAlDisc.pestanyes[id(1)]?.pane == pane("n"), "el pane surt del procés, sense la sessió")
        #expect(b.obertura.resultat == Obertura.Resultat(
            correcte: false, text: "S'ha obert «W» a Warp: 2 pestanyes, 1 amb Claude. Claude encara no ha arrencat a «T1»: mira-ho a Warp."))
    }

    /// Si entre el full i «Obre» Warp canvia el que s'obriria, no s'obre: es torna a mostrar el full.
    @Test func siWarpCanviaEsTornaAConfirmar() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        // Mentrestant, T1 s'ha obert (un Claude amb la seva marca).
        b.lectures = [despres]
        await b.obertura.confirmaIObre()
        let proposta = try #require(b.proposta)
        #expect(proposta.haCanviat)
        #expect(proposta.pla.aObrir.map(\.pestanya.id) == [id(2)])
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty)
    }

    /// Sense la finestra nova als 30 s: s'esborra igualment, i es diu.
    @Test func senseConfirmacioEsborraIgualment() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.urls.count == 1)
        #expect(b.fitxersWarp.isEmpty)
        let llancament = try #require(b.estatAlDisc.llancaments.last)
        #expect(llancament.estat == .senseConfirmar && llancament.esborrat && llancament.segons == 30)
        #expect(b.llegides == 2 + 60, "el full, la comprovació i una lectura cada 0,5 s")
        #expect(b.obertura.resultat?.correcte == false)
        #expect(b.obertura.resultat?.text.hasPrefix("No s'ha pogut confirmar que s'hagi obert «W»") == true)
    }

    /// Si Warp no l'obre, el fitxer s'esborra de seguida.
    @Test func siNoEsPotObrirEsborraElFitxer() async throws {
        let b = try Banc()
        b.fallaObrir = NoObre()
        await b.obertura.demana(id(100))
        await b.obertura.confirmaIObre()
        #expect(b.fitxersWarp.isEmpty)
        let llancament = try #require(b.estatAlDisc.llancaments.last)
        #expect(llancament.estat == .error && llancament.esborrat)
        #expect(b.obertura.resultat == Obertura.Resultat(correcte: false, text: "No s'ha pogut obrir «W» a Warp: Warp no respon"))
        #expect(b.llegides == 2, "no s'espera cap finestra")
    }

    /// Cancel·lar no deixa res; i un `estat.json` d'una versió més nova no deixa ni començar.
    @Test func cancelaIBloqueig() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        b.obertura.cancela()
        #expect(b.obertura.estat == .cap)
        await b.obertura.confirmaIObre()
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty && b.estatAlDisc.llancaments.isEmpty)

        let bloquejat = try Banc(estat: Data(#"{"versio": 9}"#.utf8))
        #expect(!bloquejat.obertura.potObrir(id(100)))
        #expect(!bloquejat.editor.potObrir(id(100)))
        await bloquejat.obertura.demana(id(100))
        #expect(bloquejat.obertura.estat == .cap && bloquejat.llegides == 0)
    }

    /// En arrencar: el fitxer d'un llançament que va quedar a mig fer s'esborra, i es diu a `estat.json`.
    @Test func netejaEnArrencar() async throws {
        let fitxer = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "T", carpeta: "/x", exec: nil)],
                                                 llancament: id(600))
        var estat = EstatApp()
        estat.desa(Llancament(id: id(600), fitxer: fitxer.nomFitxer, mida: fitxer.mida, creat: t0, finestra: id(100),
                              pestanyes: [id(2)], estat: .pendent))
        let b = try Banc(estat: try estat.json())
        _ = try b.warp.escriu(fitxer)
        b.obertura.netejaEnArrencar()
        #expect(b.fitxersWarp.isEmpty)
        let llancament = try #require(b.estatAlDisc.llancaments.last)
        #expect(llancament.esborrat && llancament.estat == .senseConfirmar)
    }

    /// El Claude de T1 surt abans que Warp desi la finestra: el fitxer s'esborra de seguida, però s'espera la finestra
    /// per lligar també T2, que és només terminal (revisió de la 0.20.0).
    @Test func laMarcaAbansQueLaFinestra() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        b.lectures = [abans, abans, nomesLaMarca, despres]
        await b.obertura.confirmaIObre()
        #expect(b.fitxersEnLlegir == [0, 0, 1, 0], "esborrat en veure la marca")
        let estat = b.estatAlDisc
        #expect(estat.pestanyes[id(1)]?.pane == pane("n") && estat.pestanyes[id(1)]?.sessio == "s-nova")
        #expect(estat.pestanyes[id(2)]?.pane == pane("m"))
        let llancament = try #require(estat.llancaments.last)
        #expect(llancament.estat == .confirmat && llancament.esborrat && llancament.segons == 1.0)
        #expect(b.obertura.resultat?.correcte == true)

        // Si la finestra no arriba mai: la marca sola no la confirma, i es diu.
        let c = try Banc()
        await c.obertura.demana(id(100))
        c.lectures = [abans, abans, nomesLaMarca]
        await c.obertura.confirmaIObre()
        #expect(c.llegides == 2 + 60)
        #expect(c.estatAlDisc.llancaments.last?.estat == .senseConfirmar)
        #expect(c.estatAlDisc.pestanyes[id(1)]?.pane == pane("n"), "el pane de la marca sí que és segur")
        #expect(c.obertura.resultat == Obertura.Resultat(correcte: false, text: "No s'ha pogut reconèixer la finestra nova "
            + "de «W» (s'ha vist Claude a 1 de 1 pestanyes): mira-la a Warp abans de tornar-la a obrir."))
    }

    /// La finestra nova, però el Claude de T1 no arrenca: s'espera fins als 30 s, i es diu. Si es tanca la finestra i
    /// es torna a obrir, T1 torna a reprendre la seva conversa (no en comença una de nova, que la hi faria perdre).
    @Test func senseElClaudeEsperaIHoDiu() async throws {
        let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
        let b = try Banc(estat: try EstatApp(pestanyes: [id(1): VincleEstat(sessio: conversa, origen: .importacio, vista: t0)])
            .json())
        let projecte = b.carpeta.appending(path: "projects/-x-t1")
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        try Data().write(to: projecte.appending(path: conversa + ".jsonl"))
        await b.obertura.demana(id(100))
        #expect(b.proposta?.pla.aObrir.first?.conversa == .repren(conversa))
        b.lectures = [abans, abans, despresSenseClaude]
        await b.obertura.confirmaIObre()
        #expect(b.llegides == 2 + 60)
        #expect(b.fitxersEnLlegir[2] == 1 && b.fitxersEnLlegir[3...].allSatisfy { $0 == 0 }, "esborrat en veure la finestra")
        let llancament = try #require(b.estatAlDisc.llancaments.last)
        #expect(llancament.estat == .confirmat && llancament.segons == 0.5)
        #expect(b.obertura.resultat == Obertura.Resultat(correcte: false, text: "S'ha obert «W» a Warp: 2 pestanyes, 1 amb "
            + "Claude. Claude encara no ha arrencat a «T1»: mira-ho a Warp."))

        b.obertura.descartaResultat()
        b.lectures = [abans]
        await b.obertura.demana(id(100))
        #expect(b.proposta?.pla.aObrir.first?.conversa == .repren(conversa))
    }

    /// Una altra pestanya (U1, a «V») recorda la mateixa conversa que T1. Mentre no es vegi el Claude de T1, U1 compta
    /// com a oberta (R9); en quant es veu, o als 10 min, ja no.
    @Test func unaConversaEnCursNoEsReprenDuesVegades() async throws {
        let conversa = "1b2c3d4e-5f60-4a7b-8c9d-0e1f2a3b4c5d"
        var config = configuracio
        config.finestres.append(Finestra(id: id(300), nom: "V", pestanyes: [
            Pestanya(id: id(3), titol: "U1", carpeta: "/x/t1", claude: .habituals),
        ]))
        let estat = EstatApp(pestanyes: [id(1): VincleEstat(sessio: conversa, origen: .importacio, vista: t0),
                                         id(3): VincleEstat(sessio: conversa, origen: .pane, vista: t0)])
        func banc() throws -> Banc {
            let b = try Banc(estat: try estat.json(), configuracio: config)
            let projecte = b.carpeta.appending(path: "projects/-x-t1")
            try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
            try Data().write(to: projecte.appending(path: conversa + ".jsonl"))
            return b
        }
        let b = try banc()
        await b.obertura.demana(id(100))
        b.lectures = [abans, abans, despresSenseClaude]
        await b.obertura.confirmaIObre()
        b.obertura.descartaResultat()

        await b.obertura.demana(id(300))
        #expect(b.proposta?.pla.obertes.map(\.on) == [.conversaEnCurs])
        #expect(b.proposta?.pla.aObrir.isEmpty == true)
        b.obertura.cancela()

        // El Claude de T1 surt (i després es tanca): U1 ja no està en curs.
        var ambClaude = despresSenseClaude
        ambClaude.finestres[1].pestanyes[0].panes[0].claude = claudeT1()
        b.llegides = 0
        b.lectures = [ambClaude, abans]
        await b.obertura.demana(id(300))
        #expect(b.proposta?.pla.obertes.map(\.on) != [.conversaEnCurs])
        b.obertura.cancela()
        await b.obertura.demana(id(300))
        #expect(b.proposta?.pla.aObrir.first?.conversa == .repren(conversa))
        b.obertura.cancela()

        // Si no se'n veu mai el Claude: als 10 min.
        let c = try banc()
        await c.obertura.demana(id(100))
        c.lectures = [abans, abans, despresSenseClaude]
        await c.obertura.confirmaIObre()
        c.obertura.descartaResultat()
        c.ara += 10 * 60
        await c.obertura.demana(id(300))
        #expect(c.proposta?.pla.aObrir.first?.conversa == .repren(conversa))
    }

    /// Una pestanya tancada fa menys d'1 minut (el seu Claude encara és viu): el full ho diu, i no s'obre res.
    @Test func ambUnaPestanyaTancadaFaPocNoSObre() async throws {
        let b = try Banc()
        var tancada = abans
        tancada.sessionsSensePestanya = [claudeT1(pane: pane("z"))]
        b.lectures = [tancada]
        await b.obertura.demana(id(100))
        let proposta = try #require(b.proposta)
        #expect(proposta.pla.motiuEspera != nil && proposta.pla.aObrir.map(\.pestanya.id) == [id(2)])
        await b.obertura.confirmaIObre()
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty && b.proposta != nil)
    }

    /// Sortir de l'app a mig obrir: el fitxer s'esborra abans de sortir, i el llançament queda sense confirmar.
    @Test func enSortirEsborraElFitxer() async throws {
        let b = try Banc()
        await b.obertura.demana(id(100))
        var enSortir: (fitxers: [String], llancament: Llancament?)?
        b.mentreObre = { [unowned b] in
            b.obertura.enSortir()
            enSortir = (b.fitxersWarp, b.estatAlDisc.llancaments.last)
        }
        await b.obertura.confirmaIObre()
        #expect(enSortir?.fitxers == [])
        #expect(enSortir?.llancament?.estat == .senseConfirmar && enSortir?.llancament?.esborrat == true)

        // Després de veure la finestra (esperant el Claude de T1): es desa confirmat, amb el pane de T2.
        let d = try Banc()
        await d.obertura.demana(id(100))
        d.lectures = [abans, abans, despresSenseClaude]
        var enSortirDespres: EstatApp?
        d.abansDeLlegir = { [unowned d] n in
            guard n == 3 else { return }
            d.obertura.enSortir()
            enSortirDespres = d.estatAlDisc
        }
        await d.obertura.confirmaIObre()
        #expect(enSortirDespres?.llancaments.last?.estat == .confirmat)
        #expect(enSortirDespres?.pestanyes[id(2)]?.pane == pane("m"))
        // Fora d'una obertura, no fa res.
        let c = try Banc()
        c.obertura.enSortir()
        #expect(c.estatAlDisc.llancaments.isEmpty)
    }

    /// Amb un `estat.json` que no es pot fer servir, la neteja no hi toca, però esborra els fitxers propis vells.
    @Test func netejaSenseEstat() async throws {
        let text = Data(#"{"versio": 9}"#.utf8)
        let b = try Banc(estat: text)
        let vell = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "T", carpeta: "/x", exec: nil)], llancament: id(601))
        let nou = try LaunchConfigWarp.genera(pestanyes: [PestanyaYAML(titol: "T", carpeta: "/x", exec: nil)], llancament: id(602))
        _ = try b.warp.escriu(vell)
        _ = try b.warp.escriu(nou)
        try FileManager.default.setAttributes([.modificationDate: t0 - 3600],
                                              ofItemAtPath: b.warp.carpeta.appending(path: vell.nomFitxer).path)
        try FileManager.default.setAttributes([.modificationDate: t0 - 30],
                                              ofItemAtPath: b.warp.carpeta.appending(path: nou.nomFitxer).path)
        b.obertura.netejaEnArrencar()
        #expect(b.fitxersWarp == [nou.nomFitxer], "el de fa 30 s potser és d'una obertura en curs")
        #expect(try Data(contentsOf: b.carpeta.appending(path: "config").appending(path: EstatApp.nomFitxer)) == text)
    }

    /// Les ordres de l'editor només demanen el full.
    @Test func lEditorNomesDemanaElFull() async throws {
        let b = try Banc()
        #expect(b.editor.potObrir(id(100)))
        b.editor.demanaObertura(id(100))
        for _ in 0..<100 where b.proposta == nil { await Task.yield() }
        #expect(b.proposta != nil)
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty)
        let senseObertura = Editor(senseCarpeta: "prova")
        #expect(!senseObertura.potObrir(id(100)))
    }
}


// MARK: - Obre-ho tot (fase 3.2)

/// «W» (T1 amb Claude, a /x/t1) i «V» (U1 amb Claude, a /x/u1); i «Buida».
private let duesFinestres = Configuracio(plantilla: .habituals, finestres: [
    Finestra(id: id(100), nom: "W", pestanyes: [Pestanya(id: id(1), titol: "T1", carpeta: "/x/t1", claude: .habituals)]),
    Finestra(id: id(300), nom: "V", pestanyes: [Pestanya(id: id(11), titol: "U1", carpeta: "/x/u1", claude: .habituals)]),
    Finestra(id: id(200), nom: "Buida"),
])

/// Sense restauració: el terminal i el Claude de cada pestanya, amb la seva marca.
private func obertesTotes(_ quines: [(UUID, String, Int32)]) -> LecturaWarp {
    senseBase(quines.map { TerminalViu(pid: $0.2, carpeta: $0.1, pane: pane("n"), marca: $0.0, claude: true) },
              sessions: quines.map {
                  SessioClaude(pid: $0.2 + 100, sessionId: "s-\($0.2)", carpeta: $0.1, iniciada: t0 + 1, ordre: ["claude"],
                               opcions: OpcionsClaude(), paneUUID: nil, dinsDeWarp: true, marca: $0.0)
              })
}

@MainActor
@Suite struct ObreTotTests {
    private var proposta: (Banc) -> Obertura.PropostaTot? = { b in
        if case let .confirmantTot(p) = b.obertura.estat { p } else { nil }
    }

    /// El full: totes les finestres amb pestanyes, totes marcades, i cap fitxer escrit.
    @Test func elFullLesMarcaTotes() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        #expect(b.obertura.potObrirTot)
        await b.obertura.demanaTot()
        let p = try #require(proposta(b))
        #expect(p.finestres.map(\.pla.finestra.nom) == ["W", "V"])
        #expect(p.triades == [id(100), id(300)])
        #expect(p.text.hasPrefix("S'obriran 2 finestres noves de Warp amb 2 pestanyes: 2 amb Claude"), "\(p.text)")
        #expect(b.fitxersWarp.isEmpty && b.urls.isEmpty)
        #expect(!b.obertura.potObrirTot, "una sola alhora")
    }

    /// Totes alhora: dues URL, els dos fitxers esborrats, els dos llançaments confirmats i el resum.
    @Test func lesObreTotesAlhora() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        b.lectures = [senseBase([]), senseBase([]), obertesTotes([(id(1), "/x/t1", 601), (id(11), "/x/u1", 701)])]
        await b.obertura.confirmaIObreTot()
        #expect(b.urls.count == 2)
        #expect(b.fitxersWarp.isEmpty)
        let llancaments = b.estatAlDisc.llancaments
        #expect(llancaments.count == 2 && llancaments.allSatisfy { $0.estat == .confirmat && $0.esborrat })
        #expect(b.obertura.resultat?.correcte == true)
        #expect(b.obertura.resultat?.text == "S'han obert 2 finestres a Warp, amb 2 pestanyes, 2 amb Claude.")
        #expect(b.obertura.estat == .cap)
    }

    /// Totes de cop (D4): la segona es demana a Warp sense esperar que s'hagi vist la primera, que aquí no es veu mai
    /// (amb una finestra rere l'altra, la segona trigaria 30 s).
    @Test func noEsperaLaPrimera() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        var quan: [Date] = []
        b.mentreObre = { [unowned b] in quan.append(b.ara) }
        await b.obertura.confirmaIObreTot()
        #expect(quan.count == 2)
        #expect(quan.count == 2 && quan[1].timeIntervalSince(quan[0]) < 5, "\(quan)")
    }

    /// Dues finestres alhora amb una pestanya de terminal a la mateixa carpeta: el terminal nou d'una no fa esborrar el
    /// fitxer de l'altra, i cap no el compta com a seu dues vegades.
    @Test func unTerminalNoComptaPerADuesFinestres() async throws {
        let b = try Banc(configuracio: Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(100), nom: "W", pestanyes: [
                Pestanya(id: id(1), titol: "T", carpeta: "/x/t", claude: ClaudePestanya(activat: false)),
            ]),
            Finestra(id: id(300), nom: "V", pestanyes: [
                Pestanya(id: id(11), titol: "T", carpeta: "/x/t", claude: ClaudePestanya(activat: false)),
            ]),
        ]))
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        // Només s'ha obert un terminal a /x/t: només una de les dues finestres el pot comptar.
        b.lectures = [senseBase([]), senseBase([]), senseBase([TerminalViu(pid: 601, carpeta: "/x/t")])]
        await b.obertura.confirmaIObreTot()
        let llancaments = b.estatAlDisc.llancaments
        #expect(llancaments.count == 2)
        #expect(llancaments.filter { $0.estat == .confirmat }.count == 1, "\(llancaments.map(\.estat))")
        #expect(b.obertura.resultat?.correcte == false)
        #expect(b.fitxersWarp.isEmpty, "als 30 s, tots dos s'esborren igualment")
    }

    /// Desmarcar una finestra en torna a calcular el pla: la conversa que li tocava queda lliure per a l'altra.
    @Test func desmarcarAlliberaLaConversa() async throws {
        let b = try Banc(configuracio: Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(100), nom: "W", pestanyes: [Pestanya(id: id(1), titol: "T1", carpeta: "/x/t1", claude: .habituals)]),
            Finestra(id: id(300), nom: "V", pestanyes: [Pestanya(id: id(11), titol: "T1 bis", carpeta: "/x/t1", claude: .habituals)]),
        ]))
        let projecte = b.carpeta.appending(path: "projects/-x-t1")
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        let conversa = "7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8)
            .write(to: projecte.appending(path: conversa + ".jsonl"))
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        #expect(proposta(b)?.finestres[1].pla.aObrir[0].conversa.repren == nil)
        let ids = proposta(b)?.llancaments
        b.obertura.tria(id(100), false)
        let p = try #require(proposta(b))
        #expect(p.finestres[1].pla.aObrir[0].conversa == .repren(conversa))
        #expect(p.llancaments == ids, "els mateixos llançaments")
        #expect(p.triades == [id(300)])
    }

    /// Una finestra desmarcada no s'obre.
    @Test func laDesmarcadaNoSObre() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        b.obertura.tria(id(300), false)
        #expect(proposta(b)?.aObrir.map(\.pla.finestra.id) == [id(100)])
        b.lectures = [senseBase([]), senseBase([]), obertesTotes([(id(1), "/x/t1", 601)])]
        await b.obertura.confirmaIObreTot()
        #expect(b.urls.count == 1)
        #expect(b.estatAlDisc.llancaments.map(\.finestra) == [id(100)])
    }

    /// Si una no s'obre, l'altra continua, i el resum ho diu.
    @Test func siUnaFallaLAltraContinua() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        let v = try #require(proposta(b)?.finestres.first { $0.pla.finestra.id == id(300) })
        b.fallaObrirLlancament = v.llancament
        b.lectures = [senseBase([]), senseBase([]), obertesTotes([(id(1), "/x/t1", 601)])]
        await b.obertura.confirmaIObreTot()
        #expect(b.urls.count == 2)
        #expect(b.fitxersWarp.isEmpty)
        #expect(b.obertura.resultat?.correcte == false)
        let text = try #require(b.obertura.resultat?.text)
        #expect(text.hasPrefix("S'han obert bé 1 de 2 finestres a Warp.\nNo s'ha pogut obrir «V» a Warp: Warp no respon"), "\(text)")
        let llancaments = b.estatAlDisc.llancaments
        #expect(llancaments.first { $0.finestra == id(100) }?.estat == .confirmat)
        #expect(llancaments.first { $0.finestra == id(300) }?.estat == .error)
    }

    /// Dues pestanyes de finestres diferents a la mateixa carpeta no reprenen mai la mateixa conversa (R9): la segona, sense
    /// cap altra conversa a la carpeta, en comença una de nova.
    @Test func duesFinestresNoReprenenLaMateixaConversa() async throws {
        let b = try Banc(configuracio: Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(100), nom: "W", pestanyes: [Pestanya(id: id(1), titol: "T1", carpeta: "/x/t1", claude: .habituals)]),
            Finestra(id: id(300), nom: "V", pestanyes: [Pestanya(id: id(11), titol: "T1 bis", carpeta: "/x/t1", claude: .habituals)]),
        ]))
        let projecte = b.carpeta.appending(path: "projects/-x-t1")
        try FileManager.default.createDirectory(at: projecte, withIntermediateDirectories: true)
        let conversa = "7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d"
        try Data((#"{"type":"user","entrypoint":"cli","message":{}}"# + "\n" + #"{"type":"assistant","message":{}}"#).utf8)
            .write(to: projecte.appending(path: conversa + ".jsonl"))
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        let p = try #require(proposta(b))
        let converses = p.finestres.map { $0.pla.aObrir[0].conversa }
        #expect(converses[0] == .repren(conversa))
        #expect(converses[1].repren == nil, "\(converses[1])")
    }

    /// Si Warp canvia entre el full i «Obre», es torna a confirmar i no s'obre res.
    @Test func siWarpCanviaEsTornaAConfirmar() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        b.lectures = [obertesTotes([(id(11), "/x/u1", 701)])]
        await b.obertura.confirmaIObreTot()
        #expect(b.urls.isEmpty)
        let p = try #require(proposta(b))
        #expect(p.haCanviat)
        #expect(p.aObrir.map(\.pla.finestra.id) == [id(100)], "V ja és oberta")
    }

    /// En sortir de l'app a mig obrir-ho tot, s'esborren tots els fitxers.
    @Test func enSortirLesEsborraTotes() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demanaTot()
        var alSortir: [String]?
        b.mentreObre = { [unowned b] in
            if b.urls.count == 2 {
                b.obertura.enSortir()
                alSortir = b.fitxersWarp
            }
        }
        b.lectures = [senseBase([])]
        await b.obertura.confirmaIObreTot()
        #expect(alSortir == [])
    }
}

/// Les pestanyes que Warp ha restaurat sola, sense Claude (06/11/2026): el full ho diu, però deixa obrir.
@MainActor
@Suite struct TerminalsDesconegutsTests {
    @Test func elFullDiuQuantesNoReconeix() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([TerminalViu(pid: 900, carpeta: "/x/altra"), TerminalViu(pid: 901, carpeta: "/x/t1")])]
        await b.obertura.demanaTot()
        guard case let .confirmantTot(p) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(p.terminalsDesconeguts == 2)
        #expect(p.aObrir.count == 2, "deixa obrir")
    }

    /// La pestanya de l'app amb marca no compta. La de terminal (T2), sense la base de Warp no es reconeix (L4) i es tornaria
    /// a obrir: compta, perquè quedaria repetida.
    @Test func ambMarcaNoCompta() async throws {
        let b = try Banc()
        b.lectures = [senseBase([TerminalViu(pid: 602, carpeta: "/x/t2"),
                                 TerminalViu(pid: 601, carpeta: "/x/t1", pane: pane("n"), marca: id(1), claude: true)])]
        await b.obertura.demanaTot()
        guard case let .confirmantTot(p) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(p.aObrir.flatMap(\.pla.aObrir).map(\.pestanya.titol) == ["T2"])
        #expect(p.terminalsDesconeguts == 1)
    }

    /// Amb Warp tancat no n'hi ha cap.
    @Test func ambWarpTancatCap() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([], warpObert: false)]
        await b.obertura.demanaTot()
        guard case let .confirmantTot(p) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(p.terminalsDesconeguts == 0)
    }
}

/// En iniciar sessió (D3): espera Warp i prepara el full de «Obre-ho tot», sense obrir res.
@MainActor
@Suite struct EnIniciarSessioTests {
    /// El full surt de seguida, sense esperar Warp (en David, 06/11/2026), i no obre res.
    @Test func elFullSurtDeSeguida() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        #expect(await b.obertura.enIniciarSessio() == .mostra)
        guard case let .confirmantTot(p) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(p.aObrir.count == 2 && !p.warpTancat)
        #expect(b.ara == t0, "cap espera")
        #expect(b.urls.isEmpty && b.fitxersWarp.isEmpty && b.engegades == 0)
    }

    /// Amb Warp tancat (no és als ítems d'inici), el full surt igualment, de seguida, i diu que l'obrirà; si Warp s'obre sol
    /// abans del clic, el clic no l'engega una altra vegada.
    @Test func ambWarpTancatElFullDiuQueLObrira() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([], warpObert: false)]
        #expect(await b.obertura.enIniciarSessio() == .mostra)
        guard case let .confirmantTot(p) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(p.warpTancat)
        #expect(b.ara == t0 && b.urls.isEmpty && b.engegades == 0)
        // Warp s'obre sol abans del clic.
        b.lectures = [senseBase([]), senseBase([]), obertesTotes([(id(1), "/x/t1", 601), (id(11), "/x/u1", 701)])]
        await b.obertura.confirmaIObreTot()
        #expect(b.engegades == 0 && b.urls.count == 2)
    }

    /// Totes les finestres ja són obertes: cap full, i l'editor es pot amagar.
    @Test func totesObertesCapFull() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [obertesTotes([(id(1), "/x/t1", 601), (id(11), "/x/u1", 701)])]
        #expect(await b.obertura.enIniciarSessio() == .amaga)
        #expect(b.obertura.estat == .cap)
        #expect(b.urls.isEmpty)
    }

    /// Si abans ja s'ha demanat obrir una finestra, no la trepitja ni amaga l'editor.
    @Test func noTrepitjaUnaAltraObertura() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        await b.obertura.demana(id(100))
        let abans = b.obertura.estat
        #expect(await b.obertura.enIniciarSessio() == .res)
        #expect(b.obertura.estat == abans)
    }

    /// En David demana «Obre a Warp…» mentre es prepara el full de l'inici: el seu es queda, i l'editor no s'amaga (revisió).
    @Test func unFullDemanatMentrestantEsQueda() async throws {
        let b = try Banc(configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        let seva = Obertura.Estat.preparant("W", id(900))
        b.abansDeLlegir = { [unowned b] n in
            if n == 0 { b.obertura.estat = seva }
        }
        #expect(await b.obertura.enIniciarSessio() == .res)
        #expect(b.obertura.estat == seva)
    }

    /// Amb `estat.json` que no es pot fer servir, el motiu queda a la vista (un full que no obre res), no s'amaga (revisió).
    @Test func ambEstatBloquejatEsDiuPerQue() async throws {
        let b = try Banc(estat: Data(#"{"versio": 9}"#.utf8), configuracio: duesFinestres)
        b.lectures = [senseBase([])]
        #expect(await b.obertura.enIniciarSessio() == .mostra)
        guard case let .noEsPot(motiu) = b.obertura.estat else { Issue.record("\(b.obertura.estat)"); return }
        #expect(motiu.hasPrefix("«estat.json» no es pot fer servir"))
        #expect(b.urls.isEmpty)
    }
}
