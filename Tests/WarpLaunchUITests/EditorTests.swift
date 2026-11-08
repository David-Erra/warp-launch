import Foundation
import Testing
import SwiftUI
import UniformTypeIdentifiers
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// Model de l'editor. Sempre amb una carpeta temporal, i sense desat automàtic (`retardDesat: nil`).

private let inici = "/Users/prova"

/// Carpeta temporal per a una prova. S'esborra en acabar.
private final class Temporal {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "warp-launch-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    var magatzem: MagatzemConfiguracio {
        MagatzemConfiguracio(carpeta: url.appending(path: "config"), inici: inici)
    }
}

private func contingut(_ carpeta: URL) -> [String] {
    (FileManager.default.enumerator(atPath: carpeta.path)?.allObjects as? [String] ?? []).sorted()
}

@MainActor
@Suite struct EditorTests {
    @Test func senseConfiguracioNoEsCreaRes() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        #expect(editor.estat == .senseConfiguracio)
        #expect(!editor.potEditar)
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestres.isEmpty)
        #expect(editor.desaSiCal())
        #expect(!FileManager.default.fileExists(atPath: tmp.magatzem.carpeta.path))
    }

    @Test func comencaEnBlancCreaElFitxerAmbLaPlantillaSegura() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        editor.comencaEnBlanc()
        #expect(editor.estat == .oberta)
        #expect(!editor.canvisSenseDesar)
        let desada = try #require(try tmp.magatzem.carrega()).configuracio
        #expect(desada.finestres.isEmpty)
        #expect(desada.plantilla == .perOmissio)
        #expect(!desada.plantilla.saltaPermisos)
    }

    @Test func novaFinestraAmbNomsQueNoEsRepeteixen() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        editor.comencaEnBlanc()
        editor.afegeixFinestra()
        editor.afegeixFinestra()
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestres.map(\.nom) == ["Finestra nova", "Finestra nova 2", "Finestra nova 3"])
        #expect(editor.finestraSeleccionada == editor.configuracio.finestres.last?.id)
        #expect(editor.canvisSenseDesar)
        #expect(editor.desaSiCal())
        #expect(try #require(try tmp.magatzem.carrega()).configuracio.finestres.count == 3)
    }

    @Test func desferIRefer() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        editor.comencaEnBlanc()
        editor.afegeixFinestra()
        editor.afegeixFinestra()
        #expect(editor.undoManager.undoActionName == "Nova finestra")

        editor.undoManager.undo()
        #expect(editor.configuracio.finestres.map(\.nom) == ["Finestra nova"])
        #expect(editor.finestraSeleccionada == editor.configuracio.finestres.first?.id)
        #expect(editor.undoManager.redoActionName == "Nova finestra")

        editor.undoManager.undo()
        #expect(editor.configuracio.finestres.isEmpty)
        #expect(editor.finestraSeleccionada == nil)
        #expect(!editor.undoManager.canUndo)

        editor.undoManager.redo()
        editor.undoManager.redo()
        #expect(editor.configuracio.finestres.map(\.nom) == ["Finestra nova", "Finestra nova 2"])
        #expect(editor.desaSiCal())
        #expect(try #require(try tmp.magatzem.carrega()).configuracio.finestres.count == 2)
    }

    @Test func faServirElDesferDeLaFinestra() throws {
        // A la prova 1, ⌘Z no feia res: el menú consultava el Desfés de la finestra, i l'editor registrava en el seu.
        // L'app li dona el de la finestra (groupsByEvent = true, el valor per defecte), i l'editor no el toca.
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        editor.comencaEnBlanc()
        let deLaFinestra = UndoManager()
        editor.usaUndoManager(deLaFinestra)
        #expect(editor.undoManager === deLaFinestra)
        #expect(deLaFinestra.groupsByEvent)
        editor.afegeixFinestra()
        #expect(deLaFinestra.canUndo)
        #expect(deLaFinestra.undoActionName == "Nova finestra")
        deLaFinestra.undo()
        #expect(editor.configuracio.finestres.isEmpty)
        #expect(deLaFinestra.redoActionName == "Nova finestra")
        deLaFinestra.redo()
        #expect(editor.configuracio.finestres.count == 1)
    }

    @Test func nomesFaLaCopiaDeSessioUnCop() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try m.desa(Configuracio(finestres: [Finestra(id: UUID(), nom: "a")]), sobre: nil)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        editor.afegeixFinestra()
        #expect(editor.desaSiCal())
        editor.afegeixFinestra()
        #expect(editor.desaSiCal())
        #expect(contingut(m.copies).count == 1)
    }

    @Test func laCopiaDeSessioEsFaEncaraQueElPrimerDesatNoCanviiRes() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try m.desa(Configuracio(finestres: [Finestra(id: UUID(), nom: "a")]), sobre: nil)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        editor.afegeixFinestra()
        editor.undoManager.undo()
        #expect(editor.desaSiCal())  // no canvia res: ni escriu ni copia
        #expect(contingut(m.copies).isEmpty)
        editor.afegeixFinestra()
        #expect(editor.desaSiCal())
        #expect(contingut(m.copies).count == 1)
    }

    @Test func senseCarpetaNoEsLlegeixNiEsCreaRes() {
        // L'app oberta amb un `--config` mal escrit: l'editor diu per què, i no s'hi pot fer res.
        let editor = Editor(senseCarpeta: "argument desconegut «--confg»")
        editor.carrega()
        #expect(editor.estat == .error("argument desconegut «--confg»"))
        #expect(!editor.potEditar)
        editor.comencaEnBlanc()
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestres.isEmpty)
        #expect(editor.desaSiCal())
        #expect(!editor.canvisSenseDesar)
    }

    @Test func unCanviForaDeLAppNoEsTrepitja() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try m.desa(Configuracio(finestres: [Finestra(id: UUID(), nom: "a")]), sobre: nil)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        // En David edita el fitxer a mà mentre l'editor és obert.
        let deFora = try Configuracio(finestres: [Finestra(id: UUID(), nom: "de fora")]).json()
        try deFora.write(to: m.fitxer)

        editor.afegeixFinestra()
        #expect(!editor.desaSiCal())
        #expect(editor.errorDesat == .modificadaFora)
        #expect(try Data(contentsOf: m.fitxer) == deFora)

        editor.carrega()
        #expect(editor.errorDesat == nil)
        #expect(!editor.canvisSenseDesar)
        #expect(editor.configuracio.finestres.map(\.nom) == ["de fora"])
        #expect(!editor.undoManager.canUndo)
    }

    @Test func unFitxerMalmesNoEsPotEditar() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        let malmes = Data("{\"versio\": 1,".utf8)
        try malmes.write(to: m.fitxer)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        guard case .error = editor.estat else {
            Issue.record("s'esperava .error, i és \(editor.estat)")
            return
        }
        editor.afegeixFinestra()
        editor.comencaEnBlanc()
        #expect(editor.configuracio.finestres.isEmpty)
        #expect(try Data(contentsOf: m.fitxer) == malmes)
    }

    @Test func elDesatAutomaticDesaSol() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: .milliseconds(10))
        editor.carrega()
        editor.comencaEnBlanc()
        editor.afegeixFinestra()
        #expect(editor.canvisSenseDesar)
        for _ in 0..<200 where editor.canvisSenseDesar { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!editor.canvisSenseDesar)
        #expect(try #require(try tmp.magatzem.carrega()).configuracio.finestres.count == 1)
    }
}

@MainActor
@Suite struct EstatWarpTests {
    private static func pane(claude: Bool) -> PaneLlegit {
        PaneLlegit(uuid: UUID().uuidString, carpeta: "/x", origenCarpeta: .pane, carpetaExisteix: true,
                   claude: claude ? SessioClaude(pid: 1, sessionId: "s", carpeta: "/x", ordre: ["claude"],
                                                 opcions: OpcionsClaude(), dinsDeWarp: true) : nil)
    }

    @Test func resumeixLaLectura() async {
        let lectura = LecturaWarp(finestres: [
            FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
                PestanyaLlegida(posicio: 0, panes: [Self.pane(claude: true)]),
                PestanyaLlegida(posicio: 1, panes: [Self.pane(claude: false), Self.pane(claude: true)]),
            ]),
            FinestraLlegida(numero: 2, pestanyaActiva: 0, pestanyes: [PestanyaLlegida(posicio: 0, panes: [Self.pane(claude: false)])]),
        ], sessionsSensePestanya: [], avisos: [])
        let warp = EstatWarp(lector: { lectura })
        #expect(warp.estat == .senseLlegir)
        await warp.llegeix()
        #expect(warp.estat == .llegit(ResumWarp(finestres: 2, pestanyes: 3, sessionsClaude: 2)))
        #expect(warp.descripcio == "Warp: 2 finestres · 3 pestanyes · 2 sessions de Claude")
    }

    @Test func unErrorDeLecturaEsDiu() async {
        struct ErrorDeProva: Error, CustomStringConvertible { var description: String { "base bloquejada" } }
        let warp = EstatWarp(lector: { throw ErrorDeProva() })
        await warp.llegeix()
        #expect(warp.estat == .error("base bloquejada"))
        #expect(warp.descripcio == "Warp: no s'ha pogut llegir (base bloquejada)")
    }
}

// MARK: - Ordres de l'editor (pas 7)

/// UUID fix: `id(7)` és `00000000-0000-0000-0000-000000000007`.
private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

/// Id nous a partir de 900, en ordre.
private final class Ids {
    private var seguent = 900
    func nou() -> UUID {
        defer { seguent += 1 }
        return id(seguent)
    }
}

private func pestanya(_ n: Int, carpeta: String? = nil) -> Pestanya {
    Pestanya(id: id(n), titol: "p\(n)", carpeta: carpeta ?? "\(inici)/GitHub/p\(n)", claude: .habituals)
}

/// Desada: «a» amb p11, p12 i p13, i «b» amb p21. Totes les carpetes existeixen, excepte les de `/perduda`.
@MainActor
private func editorAmbMostra(_ tmp: Temporal, retard: Duration? = nil) throws -> Editor {
    try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
        Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11), pestanya(12), pestanya(13)]),
        Finestra(id: id(2), nom: "b", pestanyes: [pestanya(21)]),
    ]), sobre: nil)
    let ids = Ids()
    let editor = Editor(magatzem: tmp.magatzem, retardDesat: retard, carpetaExisteix: { !$0.contains("/perduda") },
                        nouId: ids.nou)
    editor.carrega()
    return editor
}

@MainActor
private func titols(_ editor: Editor) -> [[String]] {
    editor.configuracio.finestres.map { $0.pestanyes.map(\.titol) }
}

/// Els motius de les còpies que hi ha a `copies/`.
private func motius(_ m: MagatzemConfiguracio) -> [String] {
    contingut(m.copies).map { nom in
        let parts = nom.dropLast(".json".count).split(separator: "-")
        return String(parts[3])
    }
}

@MainActor
@Suite struct EditorOrdresTests {
    @Test func cadaOrdreTeElSeuNomIEsDesfaAmbLaSeleccio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let original = editor.configuracio
        #expect(editor.finestraSeleccionada == id(1))

        typealias Ordre = (nom: String, fes: (Editor) -> Void)
        let ordres: [Ordre] = [
            ("Nova finestra", { $0.afegeixFinestra() }),
            ("Canvia el nom", { $0.reanomenaFinestra(id(1), a: "feina") }),
            ("Elimina la finestra", { $0.eliminaFinestra(id(1)) }),
            ("Duplica la finestra", { $0.duplicaFinestra(id(1)) }),
            ("Nova pestanya", { $0.afegeixPestanya(carpeta: "\(inici)/GitHub/nova") }),
            ("Duplica les pestanyes", { $0.duplicaPestanyes() }),
            ("Elimina les pestanyes", { $0.eliminaPestanyes() }),
            ("Canvia el nom", { $0.reanomenaPestanya(id(12), a: "Botiga") }),
            ("Mou les pestanyes", { $0.mouPestanyes([id(11), id(12)], a: id(2)) }),
            ("Canvia la carpeta", { $0.canviaCarpeta([id(11), id(12)], a: "\(inici)/perduda") }),
            ("Desactiva Claude", { $0.activaClaude([id(11), id(12)], false) }),
            ("Canvia l'esforç", { $0.canviaClaude([id(11), id(12)], nom: "Canvia l'esforç") { $0.esforc = "max" } }),
        ]
        for ordre in ordres {
            editor.finestraSeleccionada = id(1)
            editor.pestanyesSeleccionades = [id(11), id(12)]
            ordre.fes(editor)
            #expect(editor.configuracio != original, "\(ordre.nom)")
            #expect(editor.undoManager.undoActionName == ordre.nom)
            let despres = (editor.configuracio, editor.finestraSeleccionada, editor.pestanyesSeleccionades)

            editor.undoManager.undo()
            #expect(editor.configuracio == original, "\(ordre.nom)")
            #expect(editor.finestraSeleccionada == id(1), "\(ordre.nom)")
            #expect(editor.pestanyesSeleccionades == [id(11), id(12)], "\(ordre.nom)")
            #expect(editor.undoManager.redoActionName == ordre.nom)

            editor.undoManager.redo()
            #expect(editor.configuracio == despres.0, "\(ordre.nom)")
            #expect(editor.finestraSeleccionada == despres.1, "\(ordre.nom)")
            #expect(editor.pestanyesSeleccionades == despres.2, "\(ordre.nom)")
            editor.undoManager.undo()
        }
        // Una ordre que no canvia res no fa cap pas de Desfés.
        editor.undoManager.removeAllActions()
        editor.reanomenaFinestra(id(1), a: "  ")
        editor.mouPestanyes([id(11)], a: id(1), index: 0)
        #expect(!editor.undoManager.canUndo)
    }

    @Test func laSeleccioDespresDeCadaOrdre() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.afegeixPestanya(carpeta: "\(inici)/GitHub/nova")
        #expect(titols(editor)[0] == ["p11", "nova", "p12", "p13"])
        #expect(editor.pestanyes.map(\.titol) == ["nova"])
        // A `~`, sense Claude.
        editor.afegeixPestanya(carpeta: inici)
        #expect(editor.pestanyes.map(\.titol) == ["Pestanya nova"])
        #expect(editor.pestanyes.first?.claude.activat == false)

        editor.pestanyesSeleccionades = [id(12), id(13)]
        editor.duplicaPestanyes()
        #expect(titols(editor)[0] == ["p11", "nova", "Pestanya nova", "p12", "p13", "p12", "p13"])
        #expect(editor.pestanyes.map(\.titol) == ["p12", "p13"])
        #expect(!editor.pestanyesSeleccionades.contains(id(12)))

        editor.pestanyesSeleccionades = [id(12)]
        editor.eliminaPestanyes()
        #expect(editor.pestanyes.map(\.id) == [id(13)], "queda seleccionada la següent")
        editor.pestanyesSeleccionades = [id(13)]
        editor.mouPestanyes([id(13)], a: id(2))
        #expect(editor.finestraSeleccionada == id(2), "la selecció segueix la pestanya")
        #expect(editor.pestanyesSeleccionades == [id(13)])

        editor.finestraSeleccionada = id(1)
        #expect(editor.pestanyesSeleccionades.isEmpty, "canviar de finestra treu la selecció de pestanyes")
        editor.eliminaFinestra(id(1))
        #expect(editor.finestraSeleccionada == id(2))
        editor.duplicaFinestra(id(2))
        #expect(editor.finestra?.nom == "b còpia")
    }

    @Test func elsCanvisDeTextFanUnSolPasDeDesfes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        for model in ["o", "op", "opu", "opus"] {
            editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = model }
        }
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == "opus")
        editor.canviaClaude([id(11)], nom: "Canvia el nom fix", agrupa: "nom") { $0.nom = "Botiga" }
        editor.acabaAgrupacio()
        editor.canviaClaude([id(11)], nom: "Canvia el nom fix", agrupa: "nom") { $0.nom = "Botiga 2" }

        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == "Botiga")
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == nil)
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == nil)
        #expect(!editor.undoManager.canUndo)
    }

    @Test func elsAvisosVanAlDia() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.avisos.compta(.avis) == 0)
        editor.canviaCarpeta([id(11)], a: "\(inici)/perduda")
        #expect(editor.avisos.pestanyes[id(11)]?.map(\.tipus) == [.carpetaNoExisteix, .ultracode])
        editor.undoManager.undo()
        #expect(editor.avisos.pestanyes[id(11)]?.map(\.tipus) == [.ultracode])
    }

    @Test func nCanvisFanUnSolDesat() async throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp, retard: .milliseconds(100))
        for n in 0..<10 { editor.reanomenaPestanya(id(11), a: "títol \(n)") }
        #expect(editor.escriptures == 0)
        for _ in 0..<300 where editor.canvisSenseDesar { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!editor.canvisSenseDesar)
        #expect(editor.escriptures == 1)
        #expect(try #require(try tmp.magatzem.carrega()).configuracio.pestanya(id(11))?.titol == "títol 9")
    }

    @Test func unErrorEsDiuIEsPotTornarAProvar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let m = tmp.magatzem
        let abans = try Data(contentsOf: m.fitxer)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: m.fitxer.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path) }

        editor.reanomenaFinestra(id(1), a: "feina")
        #expect(!editor.desaSiCal())
        guard case .escriptura? = editor.errorDesat else {
            Issue.record("s'esperava un error d'escriptura, i és \(String(describing: editor.errorDesat))")
            return
        }
        #expect(editor.canvisSenseDesar)
        #expect(try Data(contentsOf: m.fitxer) == abans)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path)
        #expect(editor.desaSiCal())
        #expect(editor.errorDesat == nil)
        #expect(try #require(try m.carrega()).configuracio.finestres.first?.nom == "feina")
    }

    @Test func unCanviExternEsTornaACarregarSiNoHiHaCanvis() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let m = tmp.magatzem
        editor.comprovaCanviExtern()
        #expect(editor.configuracio.finestres.count == 2, "sense canvis al disc no fa res")

        // Sense canvis a l'app: es torna a carregar.
        editor.afegeixFinestra()
        #expect(editor.desaSiCal())
        try Configuracio(finestres: [Finestra(id: id(5), nom: "de fora")]).json().write(to: m.fitxer)
        editor.comprovaCanviExtern()
        #expect(editor.configuracio.finestres.map(\.nom) == ["de fora"])
        #expect(!editor.undoManager.canUndo, "el Desfés d'abans ja no val")
        #expect(editor.errorDesat == nil)

        // Amb canvis a l'app: no es toca res, i es diu.
        editor.afegeixFinestra()
        let deFora = try Configuracio(finestres: [Finestra(id: id(6), nom: "altra vegada")]).json()
        try deFora.write(to: m.fitxer)
        editor.comprovaCanviExtern()
        #expect(editor.errorDesat == .modificadaFora)
        #expect(editor.configuracio.finestres.count == 2)
        #expect(!editor.desaSiCal())
        #expect(try Data(contentsOf: m.fitxer) == deFora)
    }

    @Test func unaConfiguracioQueApareixFora() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        #expect(editor.estat == .senseConfiguracio)
        try tmp.magatzem.desa(Configuracio(finestres: [Finestra(id: id(1), nom: "a")]), sobre: nil)
        editor.comprovaCanviExtern()
        #expect(editor.estat == .oberta)
        #expect(editor.configuracio.finestres.map(\.nom) == ["a"])
    }

    @Test func eliminarUnaFinestraAmbPestanyesFaCopia() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        let editor = try editorAmbMostra(tmp)
        editor.afegeixFinestra()
        editor.afegeixFinestra()
        let buida = try #require(editor.finestraSeleccionada)
        #expect(editor.desaSiCal())
        #expect(motius(m) == ["sessio"])

        // Una finestra buida: sense còpia.
        editor.eliminaFinestra(buida)
        #expect(editor.desaSiCal())
        #expect(motius(m) == ["sessio"])

        // Una amb pestanyes: còpia abans de desar, amb el contingut d'abans. (Si és igual que l'última còpia, el
        // magatzem no en fa cap altra: per això aquí queda una finestra buida.)
        editor.eliminaFinestra(id(2))
        #expect(editor.desaSiCal())
        #expect(motius(m).sorted() == ["esborrat", "sessio"])
        // Si es desfà abans de desar, no cal cap còpia.
        editor.eliminaFinestra(id(1))
        editor.undoManager.undo()
        #expect(editor.desaSiCal())
        #expect(motius(m).count == 2)
    }

    @Test func importarICrear() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        #expect(editor.plantillaPerImportar == .perOmissio)
        #expect(editor.senseSessioPerImportar == .nomesTerminal)
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", panes: [PaneLlegit(uuid: "a", carpeta: "\(inici)/GitHub/botiga",
                                                                         origenCarpeta: .pane, carpetaExisteix: true)]),
        ])], sessionsSensePestanya: [], avisos: [])
        let importacio = editor.previsualitza(lectura)
        // Configuració nova: la pestanya no tenia Claude obert i queda només terminal (D-P5a).
        #expect(importacio.resum.ambPlantilla == 0)
        #expect(importacio.resum.senseClaudeObert == 1)
        #expect(!FileManager.default.fileExists(atPath: tmp.magatzem.carpeta.path), "previsualitzar no escriu res")

        editor.crea(amb: importacio)
        #expect(editor.estat == .oberta)
        #expect(!editor.canvisSenseDesar)
        #expect(editor.finestra?.nom == "GitHub")
        let desada = try #require(try tmp.magatzem.carrega()).configuracio
        #expect(desada.plantilla == .perOmissio)
        #expect(desada.finestres.flatMap(\.pestanyes).map(\.titol) == ["Botiga"])
        #expect(desada.finestres.flatMap(\.pestanyes).map(\.claude) == [.nomesTerminal])
        // Ja hi ha configuració: tornar a importar hi posa la plantilla (D11).
        #expect(editor.senseSessioPerImportar == .plantilla)
        #expect(editor.previsualitza(lectura).resum.ambPlantilla == 1)
        // «Crea» només quan no n'hi ha cap.
        editor.crea(amb: importacio)
        #expect(!editor.undoManager.canUndo)
    }

    @Test func tornarAImportarFaCopiaIEsDesfa() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        let editor = try editorAmbMostra(tmp)
        let original = editor.configuracio
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", panes: [PaneLlegit(uuid: "a", carpeta: "\(inici)/GitHub/botiga",
                                                                         origenCarpeta: .pane, carpetaExisteix: true)]),
        ])], sessionsSensePestanya: [], avisos: [])
        editor.substitueix(amb: editor.previsualitza(lectura))
        #expect(editor.undoManager.undoActionName == "Torna a importar")
        #expect(editor.configuracio.plantilla == original.plantilla, "la plantilla de la configuració")
        #expect(editor.finestraSeleccionada == editor.configuracio.finestres.first?.id)
        #expect(editor.desaSiCal())
        #expect(motius(m) == ["importacio"])

        editor.undoManager.undo()
        #expect(editor.configuracio == original)
        #expect(editor.desaSiCal())
        #expect(try #require(try m.carrega()).configuracio == original)
    }

    /// Sense configuració, importar dona pestanyes noves que no salten els permisos ni porten ultracode, com «Comença en
    /// blanc» (D11, revisada per en David el 07/11/2026). Les opcions es trien després, a la plantilla o a cada pestanya.
    @Test func senseConfiguracioImportaSenseSaltarElsPermisos() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        let importacio = editor.previsualitza(lecturaVariada())
        // Les dues que no tenien Claude obert queden només terminal (D-P5a); la de la sessió conserva «claude».
        #expect(importacio.resum.ambPlantilla == 0)
        #expect(importacio.resum.senseClaudeObert == 2)
        #expect(importacio.resum.ambSessio == 1)
        #expect(importacio.resum.saltenPermisos == 0)
        let pestanyes = importacio.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyes.allSatisfy { !$0.claude.saltaPermisos && !$0.claude.ultracode && !$0.claude.enBypass })
        #expect(importacio.configuracio.plantilla == .perOmissio)

        editor.crea(amb: importacio)
        let desada = try #require(try tmp.magatzem.carrega()).configuracio
        #expect(desada.plantilla == .perOmissio)
        #expect(!desada.finestres.flatMap(\.pestanyes).contains { $0.claude.saltaPermisos || $0.claude.ultracode })
    }

    /// Amb configuració, s'importa amb la seva plantilla, encara que salti els permisos: la d'en David no canvia.
    @Test func ambConfiguracioImportaAmbLaSevaPlantilla() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.configuracio.plantilla == .habituals)
        #expect(editor.plantillaPerImportar == .habituals)
        #expect(editor.senseSessioPerImportar == .plantilla)
        let importacio = editor.previsualitza(lecturaVariada())
        let dePlantilla = importacio.configuracio.finestres.flatMap(\.pestanyes)
            .filter { importacio.origens[$0.id] == .plantilla }
        #expect(dePlantilla.count == 2)
        #expect(importacio.resum.senseClaudeObert == 0, "tornar a importar no deixa cap pestanya només terminal de més")
        #expect(dePlantilla.allSatisfy { $0.claude == ClaudePestanya.habituals.perAPestanyaNova() })
        #expect(importacio.resum.saltenPermisos == 2)
    }
}

// MARK: - Casos de la revisió del pas 7

@MainActor
@Suite struct EditorRevisioTests {
    @Test func lesOrdresNomesActuenSobreElQueEsVeu() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        // Una part de la selecció marxa a «b»: deixa d'estar seleccionada.
        editor.mouPestanyes([id(12), id(13)], a: id(2))
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        editor.eliminaPestanyes()
        #expect(titols(editor) == [[], ["p21", "p12", "p13"]])

        // Encara que la selecció en tingui d'amagades, ⌫ i «Duplica» només toquen les de la finestra.
        editor.undoManager.undo()
        editor.pestanyesSeleccionades = [id(11), id(21)]
        editor.duplicaPestanyes()
        #expect(titols(editor) == [["p11", "p11"], ["p21", "p12", "p13"]])
        editor.pestanyesSeleccionades = [id(11), id(21)]
        editor.eliminaPestanyes()
        #expect(titols(editor) == [["p11"], ["p21", "p12", "p13"]])
    }

    @Test func moureAUnaFinestraQueNoHiEsNoFaRes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.mouPestanyes([id(11)], a: id(99))
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.canvisSenseDesar)
    }

    @Test func tornarAImportarConservaLaPlantillaDAra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let importacio = editor.previsualitza(lecturaDUnaPestanya())
        editor.canviaPlantilla(nom: "Canvia la plantilla") { $0.saltaPermisos = false }
        editor.substitueix(amb: importacio)
        #expect(editor.configuracio.plantilla.saltaPermisos == false)
        #expect(editor.configuracio.finestres == importacio.configuracio.finestres)
    }

    @Test func unaCopiaNomesSiElCanviHiEsEnDesar() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        let editor = try editorAmbMostra(tmp)
        editor.reanomenaFinestra(id(2), a: "b0")
        #expect(editor.desaSiCal())
        #expect(motius(m) == ["sessio"])

        // Eliminar i desfer, i després un altre canvi: al disc no s'ha esborrat res.
        editor.eliminaFinestra(id(1))
        editor.undoManager.undo()
        editor.reanomenaFinestra(id(2), a: "b1")
        #expect(editor.desaSiCal())
        #expect(motius(m) == ["sessio"])

        // La mateixa importació dues vegades: una sola còpia.
        let importacio = editor.previsualitza(lecturaDUnaPestanya())
        editor.substitueix(amb: importacio)
        #expect(editor.desaSiCal())
        editor.substitueix(amb: importacio)
        editor.reanomenaFinestra(importacio.configuracio.finestres[0].id, a: "GitHub 2")
        #expect(editor.desaSiCal())
        #expect(motius(m).sorted() == ["importacio", "sessio"])

        // Desfer la creació d'una finestra que ja s'havia desat amb pestanyes: còpia `esborrat`.
        editor.duplicaFinestra(importacio.configuracio.finestres[0].id)
        #expect(editor.desaSiCal())
        editor.undoManager.undo()
        #expect(editor.desaSiCal())
        #expect(motius(m).sorted() == ["esborrat", "importacio", "sessio"])
    }

    @Test func canviarDeSeleccioTancaLAgrupacio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "opus" }
        editor.pestanyesSeleccionades = [id(12)]
        editor.canviaClaude([id(12)], nom: "Canvia el model", agrupa: "model") { $0.model = "sonnet" }
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == "opus")
        #expect(editor.configuracio.pestanya(id(12))?.claude.model == nil)
        #expect(editor.pestanyesSeleccionades == [id(12)])

        // El mateix camp d'altres pestanyes, sense canviar la selecció (diverses seleccionades): un altre pas.
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "haiku" }
        editor.canviaClaude([id(11), id(12)], nom: "Canvia el model", agrupa: "model") { $0.model = "fable" }
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == "haiku")
    }

    @Test func unaAccioDAltriEntremigTancaLAgrupacio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let finestra = UndoManager()
        finestra.groupsByEvent = false
        editor.usaUndoManager(finestra)
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "o" }
        // Un camp de text de la finestra hi registra la seva acció.
        final class Camp {}
        let camp = Camp()
        finestra.beginUndoGrouping()
        finestra.registerUndo(withTarget: camp) { _ in }
        finestra.setActionName("Escriu")
        finestra.endUndoGrouping()
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "opus" }
        finestra.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == "o", "el primer ⌘Z ja desfà alguna cosa")

        // Canviar de Desfés també la tanca.
        let altre = UndoManager()
        altre.groupsByEvent = false
        altre.beginUndoGrouping()
        altre.registerUndo(withTarget: camp) { _ in }
        altre.endUndoGrouping()
        editor.usaUndoManager(altre)
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "opus" }
        altre.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.model == "o")
    }

    @Test func elBanerSEnVaSiElFitxerTornaASerElQueEra() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        let editor = try editorAmbMostra(tmp)
        let original = try Data(contentsOf: m.fitxer)
        editor.reanomenaFinestra(id(1), a: "feina")
        try Configuracio(finestres: [Finestra(id: id(5), nom: "de fora")]).json().write(to: m.fitxer)
        editor.comprovaCanviExtern()
        #expect(editor.errorDesat == .modificadaFora)
        try original.write(to: m.fitxer)
        editor.comprovaCanviExtern()
        #expect(editor.errorDesat == nil)
        #expect(editor.desaSiCal())
        #expect(try #require(try m.carrega()).configuracio.finestres.first?.nom == "feina")
    }

    @Test func elsAvisosEsTornenAMirarEnMostrarLEditor() throws {
        let tmp = try Temporal()
        try tmp.magatzem.desa(Configuracio(finestres: [
            Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11, carpeta: "\(inici)/GitHub/nova")]),
        ]), sobre: nil)
        nonisolated(unsafe) var existents: Set<String> = []
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { existents.contains($0) })
        editor.carrega()
        #expect(editor.avisos.pestanyes[id(11)]?.map(\.tipus) == [.carpetaNoExisteix, .ultracode])
        existents.insert("\(inici)/GitHub/nova")
        editor.enMostrar()
        #expect(editor.avisos.pestanyes[id(11)]?.map(\.tipus) == [.ultracode])
    }
}

private func lecturaDUnaPestanya() -> LecturaWarp {
    LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
        PestanyaLlegida(posicio: 0, titol: "Botiga", panes: [PaneLlegit(uuid: "a", carpeta: "\(inici)/GitHub/botiga",
                                                                     origenCarpeta: .pane, carpetaExisteix: true)]),
    ])], sessionsSensePestanya: [], avisos: [])
}

// MARK: - Barra lateral, llista i full d'importació (pas 8)

/// Desada: «a» amb p11 (carpeta perduda), p12 i p13 (a `~`), i «b» amb p21 (perduda) i p22. Amb avisos: p11, p13 i p21.
@MainActor
private func editorAmbAvisos(_ tmp: Temporal) throws -> Editor {
    try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
        Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11, carpeta: "\(inici)/perduda/p11"), pestanya(12),
                                                    pestanya(13, carpeta: inici)]),
        Finestra(id: id(2), nom: "b", pestanyes: [pestanya(21, carpeta: "\(inici)/perduda/p21"), pestanya(22)]),
    ]), sobre: nil)
    let ids = Ids()
    let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { !$0.contains("/perduda") },
                        nouId: ids.nou)
    editor.carrega()
    return editor
}

@MainActor
private func visibles(_ editor: Editor) -> [String] { editor.pestanyesVisibles.map(\.titol) }

/// Una lectura de Warp amb una mica de tot: a «GitHub», una pestanya sense Claude, una amb sessió i una a `~`; a
/// l'altra, una amb la carpeta perduda i una sense Claude.
private func lecturaVariada() -> LecturaWarp {
    func pane(_ carpeta: String, existeix: Bool = true, sessio: Bool = false) -> PaneLlegit {
        PaneLlegit(uuid: UUID().uuidString, carpeta: carpeta, origenCarpeta: .pane, carpetaExisteix: existeix,
                   claude: sessio ? SessioClaude(pid: 1, sessionId: "s", carpeta: carpeta, ordre: ["claude"],
                                                 opcions: OpcionsClaude(), dinsDeWarp: true) : nil)
    }
    return LecturaWarp(finestres: [
        FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Botiga", panes: [pane("\(inici)/GitHub/botiga")]),
            PestanyaLlegida(posicio: 1, titol: "Web", panes: [pane("\(inici)/GitHub/web", sessio: true)]),
            PestanyaLlegida(posicio: 2, titol: "", panes: [pane(inici)]),
        ]),
        FinestraLlegida(numero: 2, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "Vell", panes: [pane("\(inici)/GitHub/vell", existeix: false)]),
            PestanyaLlegida(posicio: 1, titol: "API", panes: [pane("\(inici)/GitHub/api")]),
        ]),
    ], sessionsSensePestanya: [], avisos: [])
}

@MainActor
@Suite struct BarraLateralTests {
    @Test func perRevisarAplegaLesPestanyesAmbAvisos() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        #expect(editor.nombrePerRevisar == 3)
        #expect(editor.perRevisarPerFinestra.map { $0.pestanyes.map(\.titol) } == [["p11", "p13"], ["p21"]])
        #expect(editor.avisPrincipal(id(13))?.tipus == .carpetaInici)
        #expect(editor.avisPrincipal(id(12)) == nil, "ultracode només surt a l'inspector")

        #expect(editor.lateral == .finestra(id(1)))
        editor.pestanyesSeleccionades = [id(12)]
        editor.lateral = .perRevisar
        #expect(editor.perRevisar)
        #expect(editor.finestraSeleccionada == id(1), "es manté, per tornar-hi")
        #expect(editor.pestanyesSeleccionades.isEmpty)
        #expect(visibles(editor) == ["p11", "p13", "p21"])
        #expect(editor.titol == "Per revisar")
        #expect(editor.subtitol == "3 pestanyes per revisar")
        #expect(!editor.potAfegirPestanya)
        editor.afegeixPestanya(carpeta: "\(inici)/GitHub/nova")
        #expect(!editor.undoManager.canUndo)

        // Un clic al buit de la barra lateral no canvia res.
        editor.lateral = nil
        #expect(editor.lateral == .perRevisar)

        editor.lateral = .finestra(id(2))
        #expect(!editor.perRevisar)
        #expect(visibles(editor) == ["p21", "p22"])
        #expect(editor.potAfegirPestanya)
    }

    @Test func lesOrdresAPerRevisar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(11), id(21)]
        editor.eliminaPestanyes()
        #expect(editor.undoManager.undoActionName == "Elimina les pestanyes")
        #expect(titols(editor) == [["p12", "p13"], ["p22"]])
        #expect(editor.pestanyesSeleccionades == [id(13)], "queda seleccionada la que venia després a la llista")

        editor.undoManager.undo()
        #expect(editor.perRevisar)
        #expect(editor.pestanyesSeleccionades == [id(11), id(21)])

        // Moure una pestanya des de «Per revisar» no fa canviar de llista.
        editor.mouPestanyes([id(11)], a: id(2))
        #expect(editor.perRevisar)
        #expect(editor.pestanyesSeleccionades == [id(11), id(21)])
        #expect(visibles(editor) == ["p13", "p21", "p11"])

        // Desfer des d'una finestra torna a «Per revisar».
        editor.lateral = .finestra(id(1))
        editor.undoManager.undo()
        #expect(editor.perRevisar)
    }

    @Test func unaPestanyaArregladaEsQuedaFinsQueEsTriaUnaAltra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(11)]
        editor.canviaCarpeta([id(11)], a: "\(inici)/GitHub/bona")
        #expect(editor.avisPrincipal(id(11)) == nil)
        #expect(editor.nombrePerRevisar == 2)
        #expect(visibles(editor) == ["p11", "p13", "p21"], "no desapareix mentre s'edita")
        editor.pestanyesSeleccionades = [id(13)]
        #expect(visibles(editor) == ["p13", "p21"])

        editor.pestanyesSeleccionades = []
        editor.canviaCarpeta([id(13), id(21)], a: "\(inici)/GitHub/bona")
        #expect(editor.perRevisarPerFinestra.isEmpty)
        #expect(editor.subtitol == "Res per revisar")
    }

    @Test func elTitolIElSubtitol() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        #expect(editor.titol == "a")
        #expect(editor.subtitol == "3 pestanyes · 3 amb Claude · 2 avisos")
        editor.lateral = .finestra(id(2))
        #expect(editor.subtitol == "2 pestanyes · 2 amb Claude · 1 avís")
        // Un nom repetit també compta.
        editor.reanomenaFinestra(id(2), a: "A")
        #expect(editor.avisPrincipal(finestra: id(2))?.tipus == .nomRepetit("A"))
        #expect(editor.subtitol == "2 pestanyes · 2 amb Claude · 2 avisos")
        editor.activaClaude([id(22)], false)
        editor.canviaCarpeta([id(21)], a: "\(inici)/GitHub/bona")
        editor.reanomenaFinestra(id(2), a: "b")
        #expect(editor.subtitol == "2 pestanyes · 1 amb Claude")

        // Si no es pot desar, ho diu.
        #expect(editor.desaSiCal())
        try Configuracio(finestres: [Finestra(id: id(5), nom: "de fora")]).json().write(to: tmp.magatzem.fitxer)
        editor.reanomenaFinestra(id(2), a: "c")
        #expect(!editor.desaSiCal())
        #expect(editor.subtitol == "El fitxer ha canviat fora de l'app")
    }

    @Test func unaFinestraNovaObreElNom() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.afegeixFinestra()
        let nova = try #require(editor.finestraSeleccionada)
        #expect(!editor.perRevisar, "la finestra nova queda seleccionada")
        #expect(editor.nomEnEdicio == .finestra(nova))
        #expect(editor.textDelNom == "Finestra nova")
        editor.textDelNom = "feina"
        editor.acabaNom(desant: true)
        #expect(editor.finestra?.nom == "feina")
        #expect(editor.undoManager.undoActionName == "Canvia el nom")
        editor.undoManager.undo()
        editor.comencaNom(.finestra(nova))
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(nova) == nil)
        #expect(editor.nomEnEdicio == nil, "no queda cap camp obert d'una finestra que ja no hi és")
        #expect(editor.perRevisar)
    }

    @Test func onSObreElDialegDeNovaPestanya() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        // L'última pestanya de la finestra és a `~`: no a /Users, sinó a `~`.
        #expect(editor.carpetaSuggerida == inici)
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.carpetaSuggerida == "\(inici)/GitHub")
        editor.lateral = .finestra(id(2))
        #expect(editor.carpetaSuggerida == "\(inici)/GitHub")
        editor.afegeixFinestra()
        #expect(editor.carpetaSuggerida == inici)
    }
}

@MainActor
@Suite struct LecturaPerImportarTests {
    @Test func tornaLaLecturaIEsperaLaQueJaSEstaFent() async {
        final class Comptador: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func suma() { lock.withLock { n += 1 } }
            var valor: Int { lock.withLock { n } }
        }
        let lectures = Comptador()
        let lectura = lecturaVariada()
        let warp = EstatWarp(lector: {
            lectures.suma()
            Thread.sleep(forTimeInterval: 0.05)
            return lectura
        })
        async let primera = warp.llegeix()
        async let segona = warp.llegeix()
        let (a, b) = await (primera, segona)
        #expect(a == .success(lectura))
        #expect(b == .success(lectura))
        #expect(lectures.valor == 1)
        #expect(warp.estat == .llegit(ResumWarp(lectura)))
    }

    /// El full s'obre mentre l'app ja llegeix Warp (en arrencar), i la lectura falla: el full ha de dir per què.
    @Test func quiEsperaUnaLecturaQueFallaEnRepElMotiu() async throws {
        struct SensePermis: Error, CustomStringConvertible {
            var description: String { "cal permís a Privacitat i seguretat › Arxius i carpetes" }
        }
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        let warp = EstatWarp(lector: {
            Thread.sleep(forTimeInterval: 0.05)
            throw SensePermis()
        })
        let full = try #require(FullImportacio(editor: editor, warp: warp))
        for _ in 0..<5 {
            async let arrencada = warp.llegeix()
            async let delFull: Void = full.llegeix()
            _ = await (arrencada, delFull)
            #expect(full.estat == .error("cal permís a Privacitat i seguretat › Arxius i carpetes"))
        }
    }
}

@MainActor
@Suite struct FullImportacioTests {
    /// Amb la restauració de sessió desactivada, Warp no desa les finestres (0.22.0): importar substituiria la configuració
    /// per res. El full ho diu, i no deixa confirmar.
    @Test func senseFinestresNoEsPotImportar() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        var lectura = lecturaVariada()
        lectura.warpDesaFinestres = false
        let llegida = lectura
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { llegida })))
        await full.llegeix()
        // No és cap error de lectura: la vista no hi ha de posar «No s'ha pogut llegir Warp».
        guard case let .senseFinestres(motiu) = full.estat else { Issue.record("\(full.estat)"); return }
        #expect(motiu.hasPrefix(LecturaWarp.senseFinestres))
        #expect(motiu.contains("Comença en blanc"))
        #expect(!full.potConfirmar && !full.confirma())
        #expect(!FileManager.default.fileExists(atPath: tmp.magatzem.carpeta.path))
    }

    /// Sense refresc (una carpeta de prova, `--config`), l'app no toca l'ajust de Warp i no li pot demanar que desi les
    /// finestres: el full ho diu així, i que amb la configuració de debò sí que es pot. No diu que no hi hagi res a Warp.
    /// Amb el refresc (la configuració de debò), el text de sempre.
    @Test func senseFinestresAmbUnaCarpetaDeProvaDiuPerQue() async throws {
        let tmp = try Temporal()
        var lectura = lecturaVariada()
        lectura.warpDesaFinestres = false
        let llegida = lectura

        let nova = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        nova.carrega()
        let crea = try #require(FullImportacio(editor: nova, warp: EstatWarp(lector: { llegida })))
        await crea.llegeix()
        guard case let .senseFinestres(motiu) = crea.estat else { Issue.record("\(crea.estat)"); return }
        #expect(motiu == LecturaWarp.senseFinestres + " Amb una configuració de prova (--config), l'app no toca aquest "
            + "ajust i no pot demanar a Warp que les desi. Amb la configuració de debò, sí: l'activa uns segons perquè Warp "
            + "les desi, i el torna a desactivar. Aquí, tria «Comença en blanc» i afegeix-hi les pestanyes.")
        #expect(!motiu.contains("No hi ha res per importar"))
        #expect(motiu.hasPrefix(MotiuSenseFinestres.deProva.text), "el text de «Lliga amb Warp…»")

        let existent = try editorAmbMostra(tmp)
        let substitueix = try #require(FullImportacio(editor: existent, warp: EstatWarp(lector: { llegida })))
        await substitueix.llegeix()
        guard case let .senseFinestres(motiu) = substitueix.estat else { Issue.record("\(substitueix.estat)"); return }
        #expect(motiu.contains("Amb una configuració de prova (--config)") && motiu.hasSuffix(" La configuració no canvia."))

        // Amb el refresc (la configuració de debò): Warp tancat, i la foto no té finestres.
        let warp = EstatWarp(lector: { llegida })
        warp.refresc = RefrescWarp(entorn: RefrescWarp.Entorn(ajust: { false }, posa: { _ in .jaHiEra }, warpObert: { false },
                                                              llegeixBase: { llegida }, espera: { _ in }))
        let deDebo = try #require(FullImportacio(editor: existent, warp: warp))
        await deDebo.llegeix()
        guard case let .senseFinestres(motiu) = deDebo.estat else { Issue.record("\(deDebo.estat)"); return }
        #expect(motiu == LecturaWarp.senseFinestres + " No hi ha res per importar, i la configuració no canvia.")
    }

    /// Sense cap Warp Stable (0.31.1), la lectura de l'app no té finestres (`Lector.llegeixDeLApp`): el full diu el mateix que
    /// el d'obrir, amb una carpeta de prova i amb la configuració de debò, i no que és per l'ajust. Amb Warp Preview obert,
    /// Warp Stable hi és: el text de sempre.
    @Test func senseCapWarpDiuElMateixAmbUnaCarpetaDeProvaIAmbLaDeDebo() async throws {
        let tmp = try Temporal()
        var lectura = lecturaVariada()
        lectura.finestres = []
        lectura.warpDesaFinestres = false
        lectura.warpPreview = .capWarp
        let llegida = lectura
        func ambRefresc() -> EstatWarp {
            let warp = EstatWarp(lector: { llegida })
            warp.refresc = RefrescWarp(entorn: RefrescWarp.Entorn(ajust: { false }, posa: { _ in .jaHiEra }, warpObert: { false },
                                                                  llegeixBase: { llegida }, espera: { _ in }))
            return warp
        }

        let nova = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        nova.carrega()
        for warp in [EstatWarp(lector: { llegida }), ambRefresc()] {
            let crea = try #require(FullImportacio(editor: nova, warp: warp))
            await crea.llegeix()
            #expect(crea.estat == .senseFinestres("No s'ha trobat Warp en aquest Mac: cal Warp Stable. No hi ha res per "
                + "importar: tria «Comença en blanc» i afegeix-hi les pestanyes."), "refresc: \(warp.refresc != nil)")
            #expect(!crea.potConfirmar && !crea.confirma())
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.magatzem.carpeta.path))

        let existent = try editorAmbMostra(tmp)
        for warp in [EstatWarp(lector: { llegida }), ambRefresc()] {
            let substitueix = try #require(FullImportacio(editor: existent, warp: warp))
            await substitueix.llegeix()
            #expect(substitueix.estat == .senseFinestres(WarpPreview.capWarp.text
                + " No hi ha res per importar, i la configuració no canvia."), "refresc: \(warp.refresc != nil)")
        }

        lectura.warpPreview = .nomesPreview
        let preview = lectura
        let nomesPreview = try #require(FullImportacio(editor: existent, warp: EstatWarp(lector: { preview })))
        await nomesPreview.llegeix()
        #expect(nomesPreview.estat == .senseFinestres(WarpPreview.nomesPreview.text
            + " No hi ha res per importar, i la configuració no canvia."))

        lectura.warpPreview = .obert
        let obert = lectura
        let ambStable = try #require(FullImportacio(editor: existent, warp: EstatWarp(lector: { obert })))
        await ambStable.llegeix()
        guard case let .senseFinestres(motiu) = ambStable.estat else { Issue.record("\(ambStable.estat)"); return }
        #expect(motiu.hasPrefix(MotiuSenseFinestres.deProva.text))
    }

    /// «Substitueix» amb una lectura sense cap finestra de terminal deixaria buida la configuració, i Retorn el prem.
    @Test func noSubstitueixPerUnaConfiguracioBuida() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        editor.comencaEnBlanc()
        editor.afegeixFinestra()
        let abans = editor.configuracio.finestres
        let buida = LecturaWarp(finestres: [], sessionsSensePestanya: [], avisos: [])
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { buida })))
        #expect(full.mode == .substitueix)
        await full.llegeix()
        #expect(full.importacio?.configuracio.finestres.isEmpty == true)
        #expect(!full.potConfirmar && !full.confirma())
        #expect(editor.configuracio.finestres == abans)
    }

    @Test func creaNomesQuanEsConfirma() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { !$0.contains("/vell") })
        editor.carrega()
        let lectura = lecturaVariada()
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lectura })))
        #expect(full.mode == .crea)
        #expect(full.titol == "Importa de Warp")
        #expect(full.boto == "Crea")
        #expect(!full.potConfirmar)

        await full.llegeix()
        // Sense configuració, les pestanyes que no tenien Claude obert queden només terminal (D-P5a, 07/11/2026), i
        // cap salta els permisos (D11).
        #expect(full.xifres == [
            "2 finestres · 5 pestanyes",
            "1 amb Claude, amb l'ordre de la seva sessió",
            "4 només terminal: 2 sense Claude obert, 1 a la carpeta d'inici i 1 amb una carpeta que ja no existeix",
        ])
        // L'ordre que hi tindran si s'hi activa Claude: la de la plantilla segura.
        #expect(full.ordrePlantilla == "claude")
        #expect(full.notaSenseClaudeObert == "Queden només terminal. Per obrir-hi Claude, marca «Obre Claude Code en "
            + "aquesta pestanya» a l'inspector: s'hi obrirà amb aquesta ordre.")
        #expect(full.importacio?.resum.saltenPermisos == 0)
        #expect(full.importacio?.configuracio.finestres.flatMap(\.pestanyes).contains { $0.claude.ultracode } == false)
        #expect(full.perRevisar == 2)
        #expect(full.textPerRevisar == "2 pestanyes sortiran a «Per revisar»")
        #expect(full.explicacio.hasSuffix("configuracio.json. No s'obre res de Warp ni de Claude."))
        #expect(full.importacio?.configuracio.finestres.map(\.nom) == ["GitHub", "GitHub 2"])
        #expect(!FileManager.default.fileExists(atPath: tmp.magatzem.carpeta.path), "llegir i previsualitzar no escriuen")
        #expect(editor.estat == .senseConfiguracio)

        #expect(full.potConfirmar)
        #expect(full.confirma())
        #expect(editor.estat == .oberta)
        // Tal com s'ha importat; en desar només s'hi afegeix qui l'ha escrit (`generador`).
        let desada = try #require(try tmp.magatzem.carrega()).configuracio
        let importada = try #require(full.importacio).configuracio
        #expect(desada.finestres == importada.finestres)
        #expect(desada.plantilla == .perOmissio)
        // Ja hi ha configuració: aquest full ja no pot crear-ne cap altra.
        #expect(!full.potConfirmar)
        #expect(!full.confirma())
    }

    /// «Comença en blanc» i després «Torna a importar-ho tot de Warp»: sense cap pestanya, és com una importació nova
    /// (decisió d'en David del 08/11/2026). Les que no tenien Claude obert queden només terminal, amb la plantilla de la
    /// configuració si s'hi activa Claude; el full substitueix, amb Desfés. Amb una pestanya, ja és tornar a importar.
    @Test func tornarAImportarSobreUnaConfiguracioSensePestanyesEsComUnaDeNova() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { !$0.contains("/vell") })
        editor.carrega()
        editor.comencaEnBlanc()
        editor.canviaPlantilla(nom: "Salta els permisos") { $0.saltaPermisos = true }
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestres.count == 1 && editor.senseSessioPerImportar == .nomesTerminal)
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaVariada() })))
        #expect(full.mode == .substitueix)
        await full.llegeix()
        #expect(full.xifres == [
            "2 finestres · 5 pestanyes",
            "1 amb Claude, amb l'ordre de la seva sessió",
            "4 només terminal: 2 sense Claude obert, 1 a la carpeta d'inici i 1 amb una carpeta que ja no existeix",
        ])
        #expect(full.ordrePlantilla == "claude --dangerously-skip-permissions", "la plantilla de la configuració")
        #expect(full.notaSenseClaudeObert != nil)
        #expect(full.confirma())
        #expect(editor.undoManager.undoActionName == "Torna a importar")
        let pestanyes = editor.configuracio.finestres.flatMap(\.pestanyes)
        #expect(pestanyes.map(\.claude.activat) == [false, true, false, false, false])
        #expect(!editor.configuracio.plantilla.ultracode && editor.configuracio.plantilla.saltaPermisos)
        // Ara ja hi ha pestanyes: tornar a importar hi posa la plantilla (D11).
        #expect(editor.senseSessioPerImportar == .plantilla)
        #expect(editor.previsualitza(lecturaVariada()).resum.ambPlantilla == 2)
        // Desfet, torna a no tenir cap pestanya.
        editor.undoManager.undo()
        #expect(editor.senseSessioPerImportar == .nomesTerminal)
    }

    @Test func tornarAImportarSubstitueix() async throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaVariada() })))
        #expect(full.mode == .substitueix)
        #expect(full.boto == "Substitueix")
        #expect(full.explicacio == "Substitueix el que hi ha ara (2 finestres i 4 pestanyes). Abans de desar se'n fa "
            + "una còpia, i es pot desfer amb ⌘Z. La plantilla no canvia.")
        await full.llegeix()
        // Tornar a importar no canvia (D11): les que no tenien Claude obert prenen la plantilla.
        #expect(full.xifres[1] == "3 amb Claude: 1 amb l'ordre de la seva sessió i 2 amb la plantilla")
        #expect(full.xifres[2] == "2 només terminal: 1 a la carpeta d'inici i 1 amb una carpeta que ja no existeix")
        #expect(full.ordrePlantilla == "claude --dangerously-skip-permissions --effort ultracode")
        #expect(full.notaSenseClaudeObert == nil)
        #expect(full.confirma())
        #expect(editor.undoManager.undoActionName == "Torna a importar")
        #expect(editor.configuracio.finestres.map(\.nom) == ["GitHub", "GitHub 2"])
    }

    /// Si la plantilla canvia (o es desfà) a la Configuració amb el full obert, les pestanyes previstes la porten
    /// vella: no es pot substituir fins a tornar a llegir, i llavors porten la nova.
    @Test func siLaPlantillaCanviaCalTornarALlegir() async throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaVariada() })))
        await full.llegeix()
        #expect(full.potConfirmar)
        #expect(!full.plantillaHaCanviat)
        editor.canviaPlantilla(nom: "No saltis els permisos") { $0.saltaPermisos = false }
        #expect(full.plantillaHaCanviat)
        #expect(!full.potConfirmar)
        #expect(!full.confirma())
        #expect(editor.configuracio.finestres.map(\.nom) == ["a", "b"])
        editor.desferPlantilla.undo()
        #expect(full.potConfirmar, "la plantilla torna a ser la de la previsualització")
        editor.desferPlantilla.redo()
        await full.llegeix()
        #expect(full.potConfirmar)
        #expect(full.confirma())
        let ambPlantilla = editor.configuracio.finestres.flatMap(\.pestanyes).filter { $0.claude.activat }
        #expect(!ambPlantilla.isEmpty)
        #expect(!editor.configuracio.plantilla.saltaPermisos)
    }

    /// Amb Claude apagat a la plantilla, tornar a importar no obre Claude enlloc: el full no ensenya cap ordre.
    @Test func ambLaPlantillaApagadaNoEnsenyaCapOrdre() async throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaPlantilla(nom: "No obris Claude") { $0.activat = false }
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaVariada() })))
        await full.llegeix()
        #expect(full.importacio?.resum.ambPlantilla == 0)
        #expect(full.ordrePlantilla == nil)
        #expect(full.notaSenseClaudeObert == nil)
    }

    /// Una configuració nova on cap pestanya tenia Claude obert: cap pestanya amb Claude, i les xifres ho diuen.
    @Test func unaConfiguracioNovaSenseCapClaude() async throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaDUnaPestanya() })))
        await full.llegeix()
        #expect(full.xifres == ["1 finestra · 1 pestanya", "0 amb Claude", "1 només terminal: 1 sense Claude obert"])
        #expect(full.notaSenseClaudeObert?.hasPrefix("Queda només terminal.") == true)
        #expect(full.ordrePlantilla == "claude")
    }

    @Test func unErrorDeLecturaNoDeixaConfirmar() async throws {
        struct ErrorDeProva: Error, CustomStringConvertible { var description: String { "base bloquejada" } }
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { throw ErrorDeProva() })))
        await full.llegeix()
        #expect(full.estat == .error("base bloquejada"))
        #expect(!full.potConfirmar)
        #expect(!full.confirma())
        #expect(full.xifres.isEmpty)
        #expect(editor.estat == .senseConfiguracio)
    }

    @Test func senseConfiguracioLlegibleNoEsPotImportar() throws {
        let editor = Editor(senseCarpeta: "argument desconegut")
        editor.carrega()
        #expect(FullImportacio(editor: editor, warp: EstatWarp(lector: { lecturaVariada() })) == nil)
    }
}

// MARK: - Casos de la revisió del pas 8

@MainActor
@Suite struct RevisioPas8Tests {
    @Test func elNomAMigEscriureNoEsPerd() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        // Una finestra nova i, sense prémer Retorn, una altra: la primera es queda el nom escrit.
        editor.afegeixFinestra()
        let primera = try #require(editor.finestraSeleccionada)
        editor.textDelNom = "feina"
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestra(primera)?.nom == "feina")
        #expect(editor.finestra?.nom == "Finestra nova")
        #expect(editor.nomEnEdicio == .finestra(try #require(editor.finestraSeleccionada)))

        // «Canvia el nom» d'una altra fila també desa el que s'escrivia.
        editor.textDelNom = "Planta"
        editor.comencaNom(.pestanya(id(11)))
        #expect(editor.finestra?.nom == "Planta")
        #expect(editor.textDelNom == "p11")

        // Un camp que ja no és l'actiu (el de la fila d'abans, en perdre el focus) no tanca el nou.
        editor.acabaNom(.finestra(primera), desant: true)
        #expect(editor.nomEnEdicio == .pestanya(id(11)))

        // Escapada: com era.
        editor.textDelNom = "no"
        editor.acabaNom(.pestanya(id(11)), desant: false)
        #expect(editor.nomEnEdicio == nil)
        #expect(editor.configuracio.pestanya(id(11))?.titol == "p11")

        // Amagar l'editor o sortir (l'app crida `acabaNom` sense fila) el desa.
        editor.comencaNom(.pestanya(id(12)))
        editor.textDelNom = "Botiga"
        editor.acabaNom(desant: true)
        #expect(editor.configuracio.pestanya(id(12))?.titol == "Botiga")

        // Una finestra no es queda sense nom; una pestanya sí (es veu el nom de la carpeta).
        editor.comencaNom(.finestra(id(2)))
        editor.textDelNom = "  "
        editor.acabaNom(desant: true)
        #expect(editor.configuracio.finestra(id(2))?.nom == "b")
        // Sense canvis, cap pas de Desfés.
        editor.undoManager.removeAllActions()
        editor.comencaNom(.finestra(id(2)))
        editor.acabaNom(desant: true)
        #expect(!editor.undoManager.canUndo)
    }

    @Test func elCampEsTancaSiLaFilaDesapareix() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.comencaNom(.pestanya(id(13)))
        editor.pestanyesSeleccionades = [id(13)]
        editor.eliminaPestanyes()
        #expect(editor.nomEnEdicio == nil)

        editor.comencaNom(.finestra(id(2)))
        editor.substitueix(amb: editor.previsualitza(lecturaVariada()))
        #expect(editor.nomEnEdicio == nil)

        editor.comencaNom(.finestra(editor.configuracio.finestres[0].id))
        editor.carrega()
        #expect(editor.nomEnEdicio == nil)
        // Una fila que no hi és no obre cap camp.
        editor.comencaNom(.pestanya(id(99)))
        #expect(editor.nomEnEdicio == nil)
    }

    @Test func eliminarLaFinestraRecordadaNoBuidaPerRevisar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(21)]
        editor.canviaCarpeta([id(21)], a: "\(inici)/GitHub/bona")
        editor.eliminaFinestra(id(1))
        #expect(editor.perRevisar)
        #expect(editor.finestraSeleccionada == id(2))
        #expect(editor.pestanyesSeleccionades == [id(21)])
        #expect(visibles(editor) == ["p21"], "la pestanya arreglada s'hi queda mentre és seleccionada")
        // Les seleccionades de la finestra eliminada deixen d'estar seleccionades.
        editor.undoManager.undo()
        editor.pestanyesSeleccionades = [id(11), id(21)]
        editor.eliminaFinestra(id(1))
        #expect(editor.pestanyesSeleccionades == [id(21)])
    }

    @Test func elsTextosDelFullEnSingular() async throws {
        let tmp = try Temporal()
        try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11)]),
        ]), sobre: nil)
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true })
        editor.carrega()
        let lectura = LecturaWarp(finestres: [FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
            PestanyaLlegida(posicio: 0, titol: "", panes: [PaneLlegit(uuid: "a", carpeta: inici, origenCarpeta: .pane,
                                                                     carpetaExisteix: true)]),
            PestanyaLlegida(posicio: 1, titol: "Botiga", panes: [PaneLlegit(uuid: "b", carpeta: "\(inici)/GitHub/botiga",
                                                                        origenCarpeta: .pane, carpetaExisteix: true)]),
        ])], sessionsSensePestanya: [], avisos: ["no s'han pogut llegir les sessions de Claude"])
        let full = try #require(FullImportacio(editor: editor, warp: EstatWarp(lector: { lectura })))
        #expect(full.explicacio.hasPrefix("Substitueix el que hi ha ara (1 finestra i 1 pestanya)."))
        await full.llegeix()
        #expect(full.xifres.last == "1 salta els permisos (--dangerously-skip-permissions)")
        #expect(full.textPerRevisar == "1 pestanya sortirà a «Per revisar»")
        #expect(full.avisosLectura == ["no s'han pogut llegir les sessions de Claude"])
    }

    @Test func elsAvisosDelFitxerEsDiuenFinsQueEsTanquen() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        let json = #"{"versio": 1, "finestres": [{"nom": "a", "pestanyes": [{"titol": "x", "carpeta": "/Users/prova/x", "claud": {}}]}]}"#
        try Data(json.utf8).write(to: m.fitxer)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        #expect(editor.estat == .oberta)
        #expect(!editor.avisosFormat.isEmpty)
        // Es queden després de desar (el fitxer ja no els té, però en David encara no els ha vist).
        editor.reanomenaFinestra(editor.configuracio.finestres[0].id, a: "b")
        #expect(editor.desaSiCal())
        #expect(!editor.avisosFormat.isEmpty)
        editor.descartaAvisosFormat()
        #expect(editor.avisosFormat.isEmpty)
    }
}

// MARK: - Inspector (pas 9)

@MainActor
@Suite struct InspectorTests {
    @Test func queMostraLInspector() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.contingutInspector == .finestra(try #require(editor.configuracio.finestra(id(1)))))
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.contingutInspector == .pestanya(try #require(editor.configuracio.pestanya(id(12)))))
        editor.pestanyesSeleccionades = [id(11), id(12)]
        guard case let .pestanyes(triades) = editor.contingutInspector else {
            Issue.record("havien de ser dues pestanyes")
            return
        }
        #expect(triades.map(\.titol) == ["p11", "p12"])
        // Una pestanya triada que no es veu (d'una altra finestra) no compta.
        editor.pestanyesSeleccionades = [id(21)]
        #expect(editor.contingutInspector == .finestra(try #require(editor.configuracio.finestra(id(1)))))
        editor.lateral = .perRevisar
        #expect(editor.contingutInspector == .res("Res per revisar"), "la mostra no té avisos")
        editor.canviaCarpeta([id(13)], a: "\(inici)/perduda/p13")
        #expect(editor.contingutInspector == .res("Tria una pestanya per revisar-la"))
        editor.lateral = .finestra(id(1))
        editor.eliminaFinestra(id(1))
        editor.eliminaFinestra(id(2))
        #expect(editor.contingutInspector == .res("Cap finestra"))
    }

    @Test func elsCampsAmbOpcions() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.tria(.model) == .perDefecte)
        #expect(editor.tria(.esforc) == .valor("xhigh"))
        #expect(editor.opcions(.model).map(\.text) == ["Per defecte", "Fable", "Opus", "Sonnet", "Haiku"])
        #expect(editor.opcions(.esforc).map(\.text) == ["Per defecte", "Baix", "Mitjà", "Alt", "Molt alt", "Màxim"])
        #expect(editor.opcions(.modePermisos).count == 7)

        // Valors que l'editor no ofereix: es mostren (si no, el control quedaria en blanc).
        editor.canviaClaude([id(12)], nom: "prova") {
            $0.model = "claude-opus-5-5"
            $0.esforc = "turbo"
            $0.modePermisos = "yolo"
        }
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.opcions(.model).last?.text == "claude-opus-5-5")
        #expect(editor.opcions(.esforc).last?.text == "turbo (desconegut)")
        #expect(editor.opcions(.modePermisos).last?.text == "yolo (desconegut)")
        #expect(editor.tria(.esforc) == .valor("turbo"))

        // Diverses pestanyes: «Valors diversos» primer, i un canvi les posa totes igual en un sol pas.
        editor.pestanyesSeleccionades = [id(11), id(12), id(13)]
        #expect(editor.tria(.esforc) == .diversos)
        #expect(editor.opcions(.esforc).first == Editor.Opcio(tria: .diversos, text: "Valors diversos"))
        #expect(editor.opcions(.esforc).map(\.text).contains("turbo (desconegut)"))
        editor.undoManager.removeAllActions()
        editor.tria(.esforc, a: .diversos)
        #expect(!editor.undoManager.canUndo, "«Valors diversos» no canvia res")
        editor.tria(.esforc, a: .valor("max"))
        #expect(editor.tria(.esforc) == .valor("max"))
        #expect(editor.undoManager.undoActionName == "Canvia l'esforç")
        editor.tria(.model, a: .perDefecte)
        #expect(editor.configuracio.pestanya(id(12))?.claude.model == nil)
        editor.undoManager.undo()
        editor.undoManager.undo()
        #expect(!editor.undoManager.canUndo, "dos passos, no un per pestanya")
        #expect([11, 12, 13].map { editor.configuracio.pestanya(id($0))?.claude.esforc } == ["xhigh", "turbo", "xhigh"])
        #expect(editor.configuracio.pestanya(id(12))?.claude.model == "claude-opus-5-5")
        #expect(editor.pestanyesSeleccionades == [id(11), id(12), id(13)])
    }

    @Test func elsInterruptorsDeDiversesPestanyes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaClaude([id(12)], nom: "prova") { $0.ultracode = false }
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(editor.siNo(.ultracode) == .diversos)
        #expect(editor.siNo(.continua) == .un(true))
        // Un interruptor mixt crida una vegada per pestanya: un sol pas de Desfés.
        editor.undoManager.removeAllActions()
        editor.posa(.ultracode, true)
        editor.posa(.ultracode, true)
        #expect(editor.siNo(.ultracode) == .un(true))
        #expect(editor.undoManager.undoActionName == "Activa l'ultracode")
        editor.undoManager.undo()
        #expect(!editor.undoManager.canUndo)
        #expect(editor.siNo(.ultracode) == .diversos)

        editor.posa(.continua, false)
        #expect(editor.undoManager.undoActionName == "No continuïs la conversa")
        #expect(editor.configuracio.pestanya(id(13))?.claude.continua == true, "només les triades")
    }

    @Test func queQuedaDesactivat() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        // Les habituals salten els permisos: el mode no hi fa res.
        #expect(editor.modeSenseEfecte)
        #expect(!editor.claudeApagatATotes)
        editor.posa(.saltaPermisos, false)
        #expect(!editor.modeSenseEfecte)
        #expect(editor.undoManager.undoActionName == "No saltis els permisos")
        editor.pestanyesSeleccionades = [id(12), id(13)]
        #expect(!editor.modeSenseEfecte, "valors diversos: el mode es pot canviar")
        editor.posa(.activat, false)
        #expect(editor.claudeApagatATotes)
        #expect(editor.undoManager.undoActionName == "Desactiva Claude")
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(!editor.claudeApagatATotes)
        editor.pestanyesSeleccionades = []
        #expect(!editor.claudeApagatATotes && !editor.modeSenseEfecte, "sense pestanyes no hi ha bloc de Claude")
    }

    @Test func elsCampsDeTextFanUnSolPas() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.undoManager.removeAllActions()
        // Lletra a lletra, com el camp: un sol pas fins que se'n surt.
        for text in ["B", "Bot", "Botiga"] { editor.canviaNomSessio(id(11), a: text, agrupa: "nom de la sessió") }
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == "Botiga")
        editor.acabaAgrupacio()
        editor.canviaNomSessio(id(11), a: "  ", agrupa: "nom de la sessió")
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == nil, "en blanc, sense nom")
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == "Botiga")
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.claude.nom == nil)
        #expect(!editor.undoManager.canUndo)

        for carpeta in ["/", "/Users/prova", "/Users/prova/GitHub/nova"] {
            editor.canviaCarpeta([id(11)], a: carpeta, agrupa: "carpeta")
        }
        for nom in ["B", "Botiga"] { editor.reanomenaPestanya(id(11), a: nom, agrupa: "nom") }
        for nom in ["f", "fe"] { editor.reanomenaFinestra(id(1), a: nom, agrupa: "nom") }
        #expect(editor.configuracio.pestanya(id(11))?.carpeta == "/Users/prova/GitHub/nova")
        #expect(editor.configuracio.finestra(id(1))?.nom == "fe")
        // Tres passos: el nom de la finestra, el de la pestanya i la carpeta.
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(1))?.nom == "a")
        #expect(editor.configuracio.pestanya(id(11))?.titol == "Botiga")
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.titol == "p11")
        #expect(editor.configuracio.pestanya(id(11))?.carpeta == "/Users/prova/GitHub/nova")
        editor.undoManager.undo()
        #expect(editor.configuracio.pestanya(id(11))?.carpeta == "\(inici)/GitHub/p11")
        #expect(!editor.undoManager.canUndo)
    }

    @Test func elsAvisosDeLInspector() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        let perduda = editor.avisosInspector(id(11))
        #expect(perduda.carpeta.map(\.tipus) == [.carpetaNoExisteix])
        #expect(perduda.claude.map(\.tipus) == [.ultracode])
        #expect(editor.avisosInspector(id(13)).carpeta.map(\.tipus) == [.carpetaInici])

        editor.canviaClaude([id(12)], nom: "prova") { $0.modePermisos = "plan" }
        #expect(editor.avisosInspector(id(12)).claude.map(\.tipus).contains(.saltaPermisosAmbMode("plan")))
        #expect(editor.avisosInspector(id(12)).carpeta.isEmpty)
        // «Claude és apagat» ho diu l'interruptor.
        editor.activaClaude([id(22)], false)
        #expect(editor.avisos.pestanyes[id(22)]?.map(\.tipus).contains(.claudeApagat) == true)
        #expect(editor.avisosInspector(id(22)).claude.isEmpty)
        #expect(editor.avisosInspector(id(22)).carpeta.isEmpty)
    }

    @Test func copiarLesOrdres() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let ordre = "claude --dangerously-skip-permissions --effort ultracode"
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.ordresSeleccionades == ordre)
        editor.activaClaude([id(12)], false)
        editor.pestanyesSeleccionades = [id(11), id(12), id(13)]
        #expect(editor.ordresSeleccionades == "\(ordre)\n\(ordre)", "les que només són un terminal no hi surten")
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.ordresSeleccionades.isEmpty)
        // Una pestanya amb Claude però sense ordre possible tampoc no hi surt (el bloc Ordre en diu el motiu).
        editor.canviaClaude([id(13)], nom: "prova") {
            $0.esforc = "high"
            $0.settings = "/Users/prova/settings.json"
        }
        #expect(editor.ordres([id(11), id(13)]) == ordre)
        #expect(editor.ordres([id(13)]).isEmpty)
        #expect(editor.ordres([id(21)]).isEmpty, "només les de la llista que es veu")
        #expect(editor.avisos.pestanyes[id(13)]?.contains { $0.gravetat == .error } == true)
        #expect(editor.avisosInspector(id(13)).claude.allSatisfy {
            if case .ordreImpossible = $0.tipus { false } else { true }
        })
    }

    // MARK: Revisió del pas 9

    @Test func canviarDeFinestraTancaLAgrupacio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.undoManager.removeAllActions()
        editor.reanomenaFinestra(id(1), a: "a-x", agrupa: "nom")
        editor.lateral = .finestra(id(2))
        editor.lateral = .finestra(id(1))
        editor.reanomenaFinestra(id(1), a: "a-xy", agrupa: "nom")
        editor.lateral = .perRevisar
        editor.lateral = .finestra(id(1))
        editor.reanomenaFinestra(id(1), a: "a-xyz", agrupa: "nom")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(1))?.nom == "a-xy")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(1))?.nom == "a-x")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(1))?.nom == "a")
        #expect(!editor.undoManager.canUndo)
    }

    @Test func unCampQueTornaACoEraNoDeixaCapPas() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.reanomenaFinestra(id(2), a: "abans")
        editor.pestanyesSeleccionades = [id(11)]
        // Escriure i esborrar-ho (o ⌘Z dins del camp): el pas ja no canvia res, i es treu.
        for nom in ["p11x", "p11xy", "p11x", "p11"] { editor.reanomenaPestanya(id(11), a: nom, agrupa: "nom") }
        #expect(editor.undoManager.undoActionName == "Canvia el nom")
        #expect(!editor.undoManager.canRedo, "sense cap Refés buit")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(2))?.nom == "b", "el primer ⌘Z desfà el canvi d'abans")
        editor.undoManager.redo()
        // El nom de la finestra esborrat lletra a lletra i tornat al d'abans (el camp ho fa en sortir-ne buit).
        editor.pestanyesSeleccionades = []
        for nom in ["a", "", "a"] { editor.reanomenaFinestra(id(1), a: nom, agrupa: "nom") }
        for nom in ["l", "a"] { editor.reanomenaFinestra(id(1), a: nom, agrupa: "nom") }
        #expect(editor.configuracio.finestra(id(1))?.nom == "a")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(2))?.nom == "b")
        // Després de treure'l, el camp torna a fer passos.
        editor.reanomenaFinestra(id(1), a: "c", agrupa: "nom")
        editor.reanomenaFinestra(id(1), a: "cd", agrupa: "nom")
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(1))?.nom == "a")
    }

    @Test func unModelAmbMajusculesEsLAlies() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaClaude([id(11)], nom: "prova") { $0.model = "Opus" }
        editor.canviaClaude([id(12)], nom: "prova") { $0.model = "opus" }
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.tria(.model) == .valor("opus"))
        #expect(editor.opcions(.model).map(\.text) == ["Per defecte", "Fable", "Opus", "Sonnet", "Haiku"])
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(editor.tria(.model) == .valor("opus"), "«Opus» i «opus» són el mateix àlies")
        // Els modes de permisos de Claude distingeixen majúscules: «Plan» no és «plan».
        editor.canviaClaude([id(11)], nom: "prova") { $0.modePermisos = "Plan" }
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.tria(.modePermisos) == .valor("Plan"))
        #expect(editor.opcions(.modePermisos).last?.text == "Plan (desconegut)")
    }

    @Test func onSObreElDialegDeLaCarpeta() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        let carpeta = { (n: Int) in editor.carpetaPerTriar(try #require(editor.configuracio.pestanya(id(n)))) }
        #expect(try carpeta(12) == "\(inici)/GitHub", "la pare, per veure'n les germanes")
        #expect(try carpeta(11) == inici, "/perduda no existeix: la més propera que sí")
        #expect(try carpeta(13) == inici, "a ~")
        editor.canviaCarpeta([id(12)], a: "GitHub/relativa")
        #expect(try carpeta(12) == inici)
        editor.canviaCarpeta([id(12)], a: "/Users")
        #expect(try carpeta(12) == inici, "la pare seria /")
    }

    @Test func lesOpcionsDeClaudeQuedenNormalitzades() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        // Una sessió importada que apagava l'ultracode de la configuració de Claude.
        editor.canviaClaude([id(11)], nom: "prova") {
            $0.ultracode = false
            $0.settings = #"{"ultracode":false}"#
        }
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.configuracio.pestanya(id(11))?.claude.settings == #"{"ultracode":false}"#)
        // Activar-lo el treu (el fitxer ja ho feia en desar): la memòria, l'ordre i el disc diuen el mateix.
        editor.posa(.ultracode, true)
        let claude = try #require(editor.configuracio.pestanya(id(11))?.claude)
        #expect(claude.settings == nil)
        #expect(claude.opcionsNomesLectura.isEmpty)
        editor.posa(.ultracode, false)
        #expect(try OrdreClaude.text(de: #require(editor.configuracio.pestanya(id(11))?.claude), repren: nil).get()
            == "claude --dangerously-skip-permissions --effort xhigh")
        #expect(editor.desaSiCal())
        editor.carrega()
        #expect(editor.configuracio.pestanya(id(11))?.claude == claude.ambUltracode(false))
    }
}

// MARK: - Porta-retalls

@MainActor
@Suite struct PortaRetallsEditorTests {
    @Test func copiarIEnganxarAUnaAltraFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaClaude([id(11)], nom: "prova") { $0.nom = "Botiga" }
        editor.pestanyesSeleccionades = [id(11), id(12)]
        let dades = try #require(editor.copiaPestanyes())
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21"]], "copiar no canvia res")

        editor.lateral = .finestra(id(2))
        editor.undoManager.removeAllActions()
        #expect(editor.enganxa(dades))
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p11", "p12"]])
        #expect(editor.undoManager.undoActionName == "Enganxa les pestanyes")
        let enganxades = editor.configuracio.finestres[1].pestanyes.suffix(2)
        #expect(editor.pestanyesSeleccionades == Set(enganxades.map(\.id)))
        #expect(enganxades.allSatisfy { ![id(11), id(12)].contains($0.id) }, "còpies: id nous")
        #expect(enganxades.first?.claude.nom == nil, "sense el nom fix de la sessió, com «Duplica»")

        // Amb una pestanya triada, després d'ella.
        editor.pestanyesSeleccionades = [id(21)]
        #expect(editor.enganxa(dades))
        #expect(titols(editor)[1] == ["p21", "p11", "p12", "p11", "p12"])
        editor.undoManager.undo()
        editor.undoManager.undo()
        #expect(titols(editor)[1] == ["p21"])
        #expect(!editor.undoManager.canUndo)
    }

    @Test func retallarIEnganxarEsMoure() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaClaude([id(12)], nom: "prova") { $0.nom = "Botiga" }
        editor.pestanyesSeleccionades = [id(12)]
        editor.undoManager.removeAllActions()
        let dades = try #require(editor.retallaPestanyes())
        #expect(titols(editor)[0] == ["p11", "p13"])
        #expect(editor.undoManager.undoActionName == "Retalla la pestanya")
        editor.lateral = .finestra(id(2))
        #expect(editor.enganxa(dades))
        #expect(editor.configuracio.finestres[1].pestanyes.last?.id == id(12), "la mateixa pestanya, amb el seu id")
        #expect(editor.configuracio.pestanya(id(12))?.claude.nom == "Botiga")
        #expect(editor.undoManager.undoActionName == "Enganxa la pestanya")
        editor.undoManager.undo()
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21"]])
    }

    @Test func enganxarAUnaFinestraNova() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11), id(13)]
        let dades = try #require(editor.copiaPestanyes())
        editor.afegeixFinestra()
        editor.acabaNom(desant: true)
        editor.undoManager.removeAllActions()
        #expect(editor.potEnganxar)
        #expect(editor.enganxa(dades))
        #expect(editor.finestra?.pestanyes.map(\.titol) == ["p11", "p13"])
        #expect(editor.pestanyesSeleccionades == Set(editor.finestra?.pestanyes.map(\.id) ?? []))
        editor.undoManager.undo()
        #expect(editor.finestra?.pestanyes.isEmpty == true)
        #expect(!editor.undoManager.canUndo, "un sol pas")
    }

    /// El tipus del porta-retalls no és text, i ⌘C/⌘X no hi posen res més (sense tocar el porta-retalls real).
    @Test func alPortaRetallsNomesHiVaElTipusPropi() throws {
        #expect(PortaRetallsSistema.tipus.identifier == PortaRetalls.tipus)
        #expect(PortaRetallsSistema.tipus.conforms(to: .data))
        #expect(!PortaRetallsSistema.tipus.conforms(to: .text))
        #expect(PortaRetallsSistema.proveidors(nil).isEmpty)
        let proveidors = PortaRetallsSistema.proveidors(Data("{}".utf8))
        #expect(proveidors.flatMap(\.registeredTypeIdentifiers) == [PortaRetalls.tipus])
    }

    @Test func onNoEsPotCopiarNiEnganxar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.copiaPestanyes() == nil, "cap pestanya triada")
        #expect(editor.retallaPestanyes() == nil)
        editor.pestanyesSeleccionades = [id(11)]
        let dades = try #require(editor.copiaPestanyes())
        editor.undoManager.removeAllActions()
        #expect(!editor.enganxa(Data("claude --continue".utf8)), "text: no són pestanyes")
        editor.lateral = .perRevisar
        #expect(!editor.potEnganxar)
        #expect(!editor.enganxa(dades), "a «Per revisar» no hi ha cap finestra on posar-les")
        #expect(!editor.undoManager.canUndo)
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21"]])
    }
}

private extension ClaudePestanya {
    func ambUltracode(_ valor: Bool) -> ClaudePestanya {
        var c = self
        c.ultracode = valor
        return c
    }
}

// MARK: - Arrossegar i «Mou a ▸» (pas 10)

/// Desada: «a» amb p11…p15, i «b» amb p21.
@MainActor
private func editorAmbCinc(_ tmp: Temporal) throws -> Editor {
    try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
        Finestra(id: id(1), nom: "a", pestanyes: (11...15).map { pestanya($0) }),
        Finestra(id: id(2), nom: "b", pestanyes: [pestanya(21)]),
    ]), sobre: nil)
    let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true }, nouId: Ids().nou)
    editor.carrega()
    return editor
}

@MainActor
@Suite struct ArrossegarTests {
    /// `onMove` dona les posicions com `move(fromOffsets:toOffset:)` (la doc de SwiftUI): totes les combinacions d'una
    /// finestra de 5 (31 seleccions × 6 destins).
    @Test func reordenarFaElMateixQueMove() throws {
        let tmp = try Temporal()
        let editor = try editorAmbCinc(tmp)
        let original = editor.configuracio
        let titols = original.finestres[0].pestanyes.map(\.titol)
        for mascara in 1..<(1 << 5) {
            let origens = IndexSet((0..<5).filter { mascara & (1 << $0) != 0 })
            for desti in 0...5 {
                let cas = "\(Array(origens)) → \(desti)"
                var esperat = titols
                esperat.move(fromOffsets: origens, toOffset: desti)
                editor.reordena(origens, a: desti)
                #expect(editor.finestra?.pestanyes.map(\.titol) == esperat, "\(cas)")
                if esperat == titols {
                    #expect(!editor.undoManager.canUndo, "\(cas): sense canvi, cap pas")
                } else {
                    #expect(editor.undoManager.undoActionName == (origens.count == 1 ? "Mou la pestanya" : "Mou les pestanyes"),
                            "\(cas)")
                    #expect(editor.pestanyes.map(\.titol) == origens.map { titols[$0] }, "\(cas): les mogudes, triades")
                    editor.undoManager.undo()
                    #expect(editor.configuracio == original, "\(cas)")
                    #expect(!editor.undoManager.canUndo, "\(cas): un sol pas")
                }
                editor.undoManager.removeAllActions()
            }
        }
    }

    @Test func aPerRevisarISenseEditarNoEsReordena() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        #expect(editor.potReordenar)
        editor.reordena([7], a: 0)
        #expect(!editor.undoManager.canUndo, "una posició fora de la llista no fa res")
        editor.lateral = .perRevisar
        #expect(!editor.potReordenar)
        editor.reordena([0], a: 2)
        #expect(!editor.undoManager.canUndo)
        #expect(!Editor(senseCarpeta: "prova").potReordenar)
    }

    @Test func deixarAnarAUnaAltraFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        let arrossegades = try [pestanya(12), pestanya(11)].map(PestanyaArrossegada.init)
        #expect(!editor.acceptaPestanyes(id(1)), "la finestra que es veu: ja hi són")
        #expect(editor.acceptaPestanyes(id(2)))
        #expect(editor.deixaAnar(arrossegades, a: id(2)))
        #expect(titols(editor) == [["p13"], ["p21", "p11", "p12"]], "al final, en l'ordre de la configuració")
        #expect(editor.undoManager.undoActionName == "Mou les pestanyes")
        #expect(editor.finestraSeleccionada == id(2), "la selecció segueix (pas 7)")
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21"]])
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11), id(12)])
        #expect(!editor.undoManager.canUndo, "un sol pas")
        editor.undoManager.redo()
        #expect(titols(editor) == [["p13"], ["p21", "p11", "p12"]])
    }

    @Test func arrossegarUnaFilaNoTriadaNoCanviaDeFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.deixaAnar([try PestanyaArrossegada(pestanya(12))], a: id(2)))
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
    }

    /// Una altra execució de l'app (una altra configuració) pot tenir els mateixos id: el que n'arriba no mou res.
    @Test func elQueVeDeForaNoFaRes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let deFora = try #require(PestanyaArrossegada(dades: PortaRetalls.dades([pestanya(11)])))
        #expect(deFora.id == id(11))
        #expect(deFora.origen != PestanyaArrossegada.aquestProces)
        #expect(!editor.deixaAnar([deFora], a: id(2)))
        #expect(!editor.deixaAnar([try PestanyaArrossegada(pestanya(99))], a: id(2)), "una pestanya que no hi és")
        #expect(!editor.deixaAnar([try PestanyaArrossegada(pestanya(11))], a: id(99)), "una finestra que no hi és")
        #expect(!editor.deixaAnar([try PestanyaArrossegada(pestanya(11))], a: id(1)), "on ja és")
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.canvisSenseDesar)
        #expect(PestanyaArrossegada(dades: Data("claude --continue".utf8)) == nil)
    }

    @Test func lesFinestresDeMouA() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        #expect(editor.finestresPerMoure([id(11)]).map(\.nom) == ["b"])
        #expect(!editor.potMoure([id(11)], a: id(1)))
        #expect(editor.finestresPerMoure([id(99)]).isEmpty)
        editor.lateral = .perRevisar
        #expect(editor.acceptaPestanyes(id(1)) && editor.acceptaPestanyes(id(2)))
        #expect(editor.finestresPerMoure([id(11), id(21)]).map(\.nom) == ["a", "b"])
        #expect(editor.finestresPerMoure([id(11)]).map(\.nom) == ["b"])
        editor.lateral = .finestra(id(1))
        editor.eliminaFinestra(id(2))
        #expect(editor.finestresPerMoure([id(11)]).isEmpty, "una sola finestra: «Mou a» no surt")
        #expect(Editor(senseCarpeta: "prova").finestresPerMoure([id(11)]).isEmpty)
    }

    @Test func elNomDelPasComptaLesQueEsMouen() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.mouPestanyes([id(11), id(99)], a: id(2))
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
    }

    @Test func moureAmbUnNomAMigEscriure() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(12)]
        editor.comencaNom(.pestanya(id(12)))
        editor.textDelNom = "Botiga"
        editor.reordena([1], a: 0)
        #expect(titols(editor)[0] == ["Botiga", "p11", "p13"])
        #expect(editor.nomEnEdicio == nil)
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
        // Un sol pas: amb el Desfés de la finestra (groupsByEvent), el mateix esdeveniment els ajuntaria igualment.
        editor.undoManager.undo()
        #expect(titols(editor)[0] == ["p11", "p12", "p13"])
        #expect(!editor.undoManager.canUndo)
        editor.undoManager.redo()
        #expect(titols(editor)[0] == ["Botiga", "p11", "p13"])
    }

    /// ⌘N amb un nom a mig escriure: el nom va al mateix pas que «Nova finestra».
    @Test func novaFinestraAmbUnNomAMigEscriure() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.comencaNom(.finestra(id(1)))
        editor.textDelNom = "Botiga"
        editor.afegeixFinestra()
        #expect(editor.configuracio.finestres.map(\.nom) == ["Botiga", "Finestra nova", "b"])
        #expect(editor.undoManager.undoActionName == "Nova finestra")
        editor.acabaNom(desant: false)
        editor.undoManager.undo()
        #expect(editor.configuracio.finestres.map(\.nom) == ["a", "b"])
        #expect(!editor.undoManager.canUndo)
    }

    /// A «Per revisar», una selecció de dues finestres deixada en una d'elles només hi porta les de l'altra: les que ja
    /// hi eren no salten al final.
    @Test func lesQueJaHiSonNoEsMouen() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(11), id(21)]
        #expect(editor.deixaAnar(try [pestanya(11), pestanya(21)].map(PestanyaArrossegada.init), a: id(1)))
        #expect(titols(editor) == [["p11", "p12", "p13", "p21"], ["p22"]])
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        editor.undoManager.removeAllActions()
        editor.mouA([id(11), id(21)], a: id(2))
        #expect(titols(editor) == [["p12", "p13"], ["p21", "p22", "p11"]], "«Mou a ▸ b»: p21 es queda la primera")
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
        editor.mouA([id(11), id(21)], a: id(2))
        #expect(editor.undoManager.undoActionName == "Mou la pestanya", "ja hi són totes: cap pas")
    }

    /// «Mou a ▸» sobre una fila no triada: el menú passa els id sense tocar la selecció, com en arrossegar-la.
    @Test func mouAUnaFilaNoTriadaNoCanviaDeFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        editor.mouA([id(13)], a: id(2))
        #expect(titols(editor) == [["p11", "p12"], ["p21", "p13"]])
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11), id(12)])
        editor.undoManager.undo()
        #expect(editor.finestraSeleccionada == id(1))
        #expect(editor.pestanyesSeleccionades == [id(11), id(12)])
        // Dins de la selecció: la segueix (pas 7).
        editor.mouA([id(11), id(12)], a: id(2))
        #expect(editor.finestraSeleccionada == id(2))
        #expect(editor.pestanyesSeleccionades == [id(11), id(12)])
    }

    /// Dues finestres amb el mateix nom: a «Mou a ▸» es distingeixen pel resum.
    @Test func lesEtiquetesDeMouA() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        let b = try #require(editor.configuracio.finestra(id(2)))
        #expect(editor.etiquetaPerMoure(b) == "b")
        editor.reanomenaFinestra(id(2), a: "A")
        let etiquetes = editor.configuracio.finestres.map(editor.etiquetaPerMoure)
        #expect(etiquetes == ["a — 3 pestanyes · 3 amb Claude", "A — 2 pestanyes · 2 amb Claude"])
    }

    /// El que s'arrossega és el tipus propi, només per a aquest procés, i mai text. Sense tocar cap porta-retalls.
    @Test func elQueSArrossegaNomesEsDadesDAquestaApp() async throws {
        let tipus = PortaRetallsSistema.tipus
        // No s'exporta mai: el que s'arrossega ho dona `proveidor`, només per a aquest procés.
        #expect(PestanyaArrossegada.exportedContentTypes(visibility: .all).isEmpty, "cap altra app no el veu")
        #expect(PestanyaArrossegada.exportedContentTypes(visibility: .ownProcess).isEmpty)
        #expect(PestanyaArrossegada.importedContentTypes() == [tipus])
        #expect(!tipus.conforms(to: .text))
        let arrossegada = try PestanyaArrossegada(pestanya(11))
        await #expect(throws: (any Error).self) { try await arrossegada.exported(as: .utf8PlainText) }
        await #expect(throws: (any Error).self) { try await arrossegada.exported(as: tipus) }
        let tornada = try await PestanyaArrossegada(importing: arrossegada.dades, contentType: tipus)
        #expect(tornada == arrossegada)
        #expect(tornada.origen == PestanyaArrossegada.aquestProces)
        let proveidor = try #require(PestanyaArrossegada.proveidor(pestanya(11)))
        #expect(proveidor.registeredTypeIdentifiers == [PortaRetalls.tipus])
    }
}

// MARK: - Obrir una finestra arrossegant i deixar-les anar a una posició (pas 10b)

/// Desada: «a» amb p11, p12 i p13, i «b» amb p21 i p22.
@MainActor
private func editorAmbDues(_ tmp: Temporal) throws -> Editor {
    try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
        Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11), pestanya(12), pestanya(13)]),
        Finestra(id: id(2), nom: "b", pestanyes: [pestanya(21), pestanya(22)]),
    ]), sobre: nil)
    let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true }, nouId: Ids().nou)
    editor.carrega()
    return editor
}

private func arrossegades(_ ns: [Int]) throws -> [PestanyaArrossegada] {
    try ns.map { try PestanyaArrossegada(pestanya($0)) }
}

@MainActor
@Suite struct ObrirArrossegantTests {
    @Test func nomesSObreUnaAltraFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        #expect(!editor.potObrirArrossegant(id(1)), "la que es veu")
        #expect(editor.potObrirArrossegant(id(2)))
        #expect(!editor.potObrirArrossegant(id(99)))
        editor.lateral = .perRevisar
        #expect(editor.potObrirArrossegant(id(1)) && editor.potObrirArrossegant(id(2)), "des de «Per revisar», totes")
        #expect(!Editor(senseCarpeta: "prova").potObrirArrossegant(id(1)))
    }

    /// Obrir no és cap pas de Desfés: només canvia la finestra que es veu, i la llista (`generacioLlista`).
    @Test func obrirNoEsUnPasIRecordaLaSeleccio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        editor.obreArrossegant(id(2))
        #expect(editor.lateral == .finestra(id(2)))
        #expect(editor.pestanyesSeleccionades.isEmpty)
        #expect(editor.generacioLlista == 1)
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.canvisSenseDesar)
        let abans = Editor.Seleccio(finestra: id(1), perRevisar: false, pestanyes: [id(11), id(12)])
        #expect(editor.abansDObrir == abans)
        editor.obreArrossegant(id(2))
        #expect(editor.generacioLlista == 1, "la que ja es veu: res")
        // A → B → A: es recorda la primera.
        editor.obreArrossegant(id(1))
        #expect(editor.generacioLlista == 2)
        #expect(editor.abansDObrir == abans)
        // Un clic no canvia la llista.
        editor.lateral = .finestra(id(2))
        #expect(editor.generacioLlista == 2)
    }

    /// El risc principal: després d'obrir «b» arrossegant pestanyes de «a», un `onMove` amb posicions de «a»
    /// (SwiftUI les treu de la llista d'on ha sortit l'arrossegament) mouria p22 de «b», que en David no ha tocat.
    @Test func unOnMoveDespresDObrirNoMouRes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(12)]
        editor.obreArrossegant(id(2))
        #expect(editor.potReordenar, "la llista de «b» es pot reordenar (amb un arrossegament nou)")
        editor.reordena([1], a: 0)
        editor.reordena([0, 1], a: 2)
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        #expect(!editor.undoManager.canUndo)
        // Un arrossegament nou a la llista de «b»: les posicions ja són de «b».
        editor.comencaArrossegament(id(21))
        editor.reordena([1], a: 0)
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p22", "p21"]])
    }

    /// Totes les seleccions de «a» deixades a cada posició de la llista de «b» (i una de fora): van on s'han deixat, en
    /// l'ordre de la configuració; un sol pas, que torna a «a» amb la selecció d'abans; Refés torna a «b», triades.
    @Test func deixarAnarALaLlistaDUnaAltraFinestra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        let original = editor.configuracio
        for mascara in 1..<(1 << 3) {
            let ns = (0..<3).filter { mascara & (1 << $0) != 0 }.map { 11 + $0 }
            for index in [0, 1, 2, 7] {
                let cas = "\(ns) → \(index)"
                editor.lateral = .finestra(id(1))
                editor.pestanyesSeleccionades = Set(ns.map(id))
                editor.obreArrossegant(id(2))
                #expect(editor.acceptaPestanyes(id(2)), "\(cas): la fila de la finestra oberta també")
                #expect(editor.deixaAnar(try arrossegades(ns.reversed()), a: id(2), index: index), "\(cas)")
                var b = ["p21", "p22"]
                b.insert(contentsOf: ns.map { "p\($0)" }, at: min(index, 2))
                #expect(titols(editor) == [["p11", "p12", "p13"].filter { !ns.map { "p\($0)" }.contains($0) }, b], "\(cas)")
                #expect(editor.lateral == .finestra(id(2)), "\(cas)")
                #expect(editor.pestanyesSeleccionades == Set(ns.map(id)), "\(cas): les mogudes, triades")
                #expect(editor.abansDObrir == nil, "\(cas)")
                #expect(editor.undoManager.undoActionName == (ns.count == 1 ? "Mou la pestanya" : "Mou les pestanyes"))
                editor.undoManager.undo()
                #expect(editor.configuracio == original, "\(cas)")
                #expect(editor.lateral == .finestra(id(1)), "\(cas): torna a «a»")
                #expect(editor.pestanyesSeleccionades == Set(ns.map(id)), "\(cas): amb la selecció d'abans")
                #expect(!editor.undoManager.canUndo, "\(cas): un sol pas")
                editor.undoManager.redo()
                #expect(editor.lateral == .finestra(id(2)), "\(cas)")
                #expect(editor.pestanyesSeleccionades == Set(ns.map(id)), "\(cas)")
                editor.undoManager.undo()
                editor.undoManager.removeAllActions()
            }
        }
    }

    /// Sense obrir cap finestra, deixar-les a la llista que es veu fa el mateix que `onMove` (variant sense `onMove`).
    @Test func dinsDeLaMateixaFinestraEsComReordenar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbCinc(tmp)
        let original = editor.configuracio
        let titolsA = original.finestres[0].pestanyes.map(\.titol)
        for mascara in 1..<(1 << 5) {
            let origens = IndexSet((0..<5).filter { mascara & (1 << $0) != 0 })
            for desti in 0...5 {
                var esperat = titolsA
                esperat.move(fromOffsets: origens, toOffset: desti)
                let ns = origens.map { 11 + $0 }
                editor.deixaAnar(try arrossegades(ns), a: id(1), index: desti)
                #expect(editor.finestra?.pestanyes.map(\.titol) == esperat, "\(Array(origens)) → \(desti)")
                if esperat != titolsA {
                    #expect(editor.pestanyesSeleccionades == Set(ns.map(id)))
                    editor.undoManager.undo()
                    #expect(!editor.undoManager.canUndo)
                }
                #expect(editor.configuracio == original)
                editor.undoManager.removeAllActions()
            }
        }
    }

    /// L'índex és de la llista que es veu: a una altra finestra, a «Per revisar» o sense poder editar, no es mou res.
    @Test func elQueNoEsPotDeixarALaLlista() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        #expect(!editor.deixaAnar(try arrossegades([11]), a: id(2), index: 0), "«b» no es veu")
        let deFora = try #require(PestanyaArrossegada(dades: PortaRetalls.dades([pestanya(21)])))
        #expect(!editor.deixaAnar([deFora], a: id(1), index: 0), "d'una altra execució de l'app")
        #expect(!editor.deixaAnar(try arrossegades([99]), a: id(1), index: 0), "una pestanya que no hi és")
        #expect(!editor.deixaAnar(try arrossegades([11]), a: id(99), index: 0), "una finestra que no hi és")
        #expect(!editor.deixaAnar(try arrossegades([11]), a: id(1), index: 0), "on ja és: cap canvi")
        editor.lateral = .perRevisar
        #expect(!editor.deixaAnar(try arrossegades([21]), a: id(1), index: 0))
        #expect(!Editor(senseCarpeta: "prova").deixaAnar(try arrossegades([11]), a: id(1), index: 0))
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.canvisSenseDesar)
    }

    /// Una finestra buida no s'obre arrossegant (prova 7: la llista d'origen desapareixia i no s'acceptava res
    /// enlloc). Les pestanyes es deixen a la seva fila, i la selecció les segueix.
    @Test func unaFinestraBuidaNoSObre() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.afegeixFinestra()
        editor.acabaNom(desant: false)
        let buida = try #require(editor.finestraSeleccionada)
        editor.lateral = .finestra(id(1))
        editor.undoManager.removeAllActions()
        editor.pestanyesSeleccionades = [id(12)]
        #expect(!editor.potObrirArrossegant(buida))
        editor.obreArrossegant(buida)
        #expect(editor.lateral == .finestra(id(1)), "no s'obre")
        #expect(editor.abansDObrir == nil)
        editor.lateral = .perRevisar
        #expect(!editor.potObrirArrossegant(buida), "tampoc des de «Per revisar»")
        editor.lateral = .finestra(id(1))
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.acceptaPestanyes(buida))
        #expect(editor.deixaAnar(try arrossegades([12]), a: buida))
        #expect(editor.finestra?.pestanyes.map(\.titol) == ["p12"])
        #expect(editor.lateral == .finestra(buida))
        editor.undoManager.undo()
        #expect(editor.lateral == .finestra(id(1)))
        #expect(editor.pestanyesSeleccionades == [id(12)])
        #expect(titols(editor) == [["p11", "p12", "p13"], [], ["p21", "p22"]])
    }

    /// Obrir «b» i deixar-les a la seva fila: van al final, i la selecció les segueix com abans d'obrir-la.
    @Test func aLaFilaDeLaFinestraOberta() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        #expect(!editor.acceptaPestanyes(id(1)))
        editor.obreArrossegant(id(2))
        #expect(editor.acceptaPestanyes(id(2)))
        #expect(editor.deixaAnar(try arrossegades([11]), a: id(2)))
        #expect(titols(editor) == [["p12", "p13"], ["p21", "p22", "p11"]])
        #expect(editor.lateral == .finestra(id(2)))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(!editor.acceptaPestanyes(id(2)), "ja no hi ha res obert arrossegant")
        editor.undoManager.undo()
        #expect(editor.lateral == .finestra(id(1)))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(!editor.undoManager.canUndo)
    }

    /// Una fila no triada: tant a la llista com a la fila de la finestra oberta, la que hi ha arribat queda triada.
    @Test func unaFilaNoTriadaDespresDObrir() throws {
        for aLaLlista in [true, false] {
            let tmp = try Temporal()
            let editor = try editorAmbDues(tmp)
            editor.pestanyesSeleccionades = [id(11)]
            editor.obreArrossegant(id(2))
            if aLaLlista {
                #expect(editor.deixaAnar(try arrossegades([13]), a: id(2), index: 1))
                #expect(titols(editor) == [["p11", "p12"], ["p21", "p13", "p22"]])
            } else {
                #expect(editor.deixaAnar(try arrossegades([13]), a: id(2)))
                #expect(titols(editor) == [["p11", "p12"], ["p21", "p22", "p13"]])
            }
            #expect(editor.lateral == .finestra(id(2)))
            #expect(editor.pestanyesSeleccionades == [id(13)], "a la llista: \(aLaLlista)")
            editor.undoManager.undo()
            #expect(editor.lateral == .finestra(id(1)))
            #expect(editor.pestanyesSeleccionades == [id(11)])
            #expect(!editor.undoManager.canUndo)
        }
    }

    /// Obrir «b» i deixar-les a la fila d'una tercera finestra: hi van al final, l'editor les segueix (eren les
    /// triades d'abans d'obrir), i ⌘Z torna a «a».
    @Test func aLaFilaDUnaTerceraFinestra() throws {
        let tmp = try Temporal()
        try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: [
            Finestra(id: id(1), nom: "a", pestanyes: [pestanya(11), pestanya(12), pestanya(13)]),
            Finestra(id: id(2), nom: "b", pestanyes: [pestanya(21), pestanya(22)]),
            Finestra(id: id(3), nom: "c", pestanyes: [pestanya(31)]),
        ]), sobre: nil)
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true }, nouId: Ids().nou)
        editor.carrega()
        editor.pestanyesSeleccionades = [id(11)]
        editor.obreArrossegant(id(2))
        #expect(editor.deixaAnar(try arrossegades([11]), a: id(3)))
        #expect(titols(editor) == [["p12", "p13"], ["p21", "p22"], ["p31", "p11"]])
        #expect(editor.lateral == .finestra(id(3)))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        editor.undoManager.undo()
        #expect(editor.lateral == .finestra(id(1)))
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(!editor.undoManager.canUndo)
    }

    /// A → B → A: la llista d'«a» és nova, i la pestanya va a la posició on es deixa, pels id.
    @Test func obrirIAltraVegadaLaDOrigen() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(13)]
        editor.obreArrossegant(id(2))
        editor.obreArrossegant(id(1))
        #expect(editor.generacioLlista == 2)
        #expect(editor.deixaAnar(try arrossegades([13]), a: id(1), index: 0))
        #expect(titols(editor)[0] == ["p13", "p11", "p12"])
        #expect(editor.undoManager.undoActionName == "Mou la pestanya")
        #expect(editor.pestanyesSeleccionades == [id(13)])
        editor.undoManager.undo()
        #expect(titols(editor)[0] == ["p11", "p12", "p13"])
        #expect(editor.lateral == .finestra(id(1)))
        #expect(editor.pestanyesSeleccionades == [id(13)])
        #expect(!editor.undoManager.canUndo)
    }

    /// Des de «Per revisar»: s'obre «b», es deixen a la posició 0, i ⌘Z torna a «Per revisar».
    @Test func desDePerRevisar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(11)]
        editor.obreArrossegant(id(2))
        #expect(editor.lateral == .finestra(id(2)))
        #expect(editor.deixaAnar(try arrossegades([11]), a: id(2), index: 0))
        #expect(titols(editor) == [["p12", "p13"], ["p11", "p21", "p22"]])
        #expect(editor.pestanyesSeleccionades == [id(11)])
        editor.undoManager.undo()
        #expect(editor.lateral == .perRevisar)
        #expect(editor.pestanyesSeleccionades == [id(11)])
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
    }

    /// Un nom a mig escriure es desa en obrir, com amb un clic, en el seu pas; deixar-les anar és un altre.
    @Test func unNomAMigEscriure() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(12)]
        editor.comencaNom(.pestanya(id(12)))
        editor.textDelNom = "Botiga"
        editor.obreArrossegant(id(2))
        #expect(editor.nomEnEdicio == nil)
        #expect(editor.undoManager.undoActionName == "Canvia el nom")
        #expect(editor.deixaAnar(try arrossegades([12]), a: id(2), index: 1))
        #expect(titols(editor) == [["p11", "p13"], ["p21", "Botiga", "p22"]])
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "Botiga", "p13"], ["p21", "p22"]])
        #expect(editor.lateral == .finestra(id(1)))
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        #expect(!editor.undoManager.canUndo)
    }

    /// Un arrossegament cancel·lat (Esc, o deixar-les fora) després d'obrir: no canvia res, i la marca se'n va amb un
    /// arrossegament nou, un canvi, Desfés o en carregar.
    @Test func unArrossegamentCancellat() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.obreArrossegant(id(2))
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        #expect(!editor.canvisSenseDesar)
        editor.activaClaude([id(21)], false)
        #expect(editor.abansDObrir == nil, "un canvi")
        editor.reordena([1], a: 0)
        #expect(titols(editor)[1] == ["p22", "p21"])
        editor.obreArrossegant(id(1))
        #expect(editor.abansDObrir != nil)
        editor.undoManager.undo()
        #expect(editor.abansDObrir == nil, "Desfés")
        let altra = editor.lateral == .finestra(id(1)) ? id(2) : id(1)
        editor.obreArrossegant(altra)
        #expect(editor.abansDObrir != nil)
        editor.comencaArrossegament(id(11))
        #expect(editor.abansDObrir == nil, "un arrossegament nou")
        editor.obreArrossegant(editor.lateral == .finestra(id(1)) ? id(2) : id(1))
        #expect(editor.abansDObrir != nil)
        editor.carrega()
        #expect(editor.abansDObrir == nil, "carregar")
    }
}

// MARK: - Reordenar finestres

/// «a» (p11), «b» (p21), «c» (p31) i «d» (p41).
@MainActor
private func editorAmbQuatre(_ tmp: Temporal) throws -> Editor {
    try tmp.magatzem.desa(Configuracio(plantilla: .habituals, finestres: (1...4).map { n in
        Finestra(id: id(n), nom: ["a", "b", "c", "d"][n - 1], pestanyes: [pestanya(n * 10 + 1)])
    }), sobre: nil)
    let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true }, nouId: Ids().nou)
    editor.carrega()
    return editor
}

@MainActor
@Suite struct ReordenarFinestresTests {
    private func noms(_ editor: Editor) -> [String] { editor.configuracio.finestres.map(\.nom) }

    /// `onMove` de la barra lateral: com `move(fromOffsets:toOffset:)`, en totes les combinacions de 4 finestres.
    @Test func reordenarFaElMateixQueMove() throws {
        let tmp = try Temporal()
        let editor = try editorAmbQuatre(tmp)
        let original = editor.configuracio
        for mascara in 1..<(1 << 4) {
            let origens = IndexSet((0..<4).filter { mascara & (1 << $0) != 0 })
            for desti in 0...4 {
                var esperat = ["a", "b", "c", "d"]
                esperat.move(fromOffsets: origens, toOffset: desti)
                editor.comencaArrossegamentDeFinestra()
                editor.reordenaFinestres(origens, a: desti)
                #expect(noms(editor) == esperat, "\(Array(origens)) → \(desti)")
                #expect(editor.lateral == .finestra(id(1)), "la finestra que es veu no canvia")
                if esperat != ["a", "b", "c", "d"] {
                    #expect(editor.undoManager.undoActionName == (origens.count == 1 ? "Mou la finestra" : "Mou les finestres"))
                    editor.undoManager.undo()
                    #expect(editor.configuracio == original)
                    #expect(!editor.undoManager.canUndo, "un sol pas")
                } else {
                    #expect(!editor.undoManager.canUndo, "sense canvi, cap pas")
                }
                editor.undoManager.removeAllActions()
            }
        }
    }

    /// Sense la marca d'una fila de finestra, unes posicions no mouen res: podrien ser les de la llista de pestanyes.
    /// I amb la marca, la llista de pestanyes no es reordena ni s'obre cap finestra arrossegant.
    @Test func lesDuesLlistesNoEsBarregen() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.reordenaFinestres([0], a: 2)
        #expect(editor.configuracio.finestres.map(\.nom) == ["a", "b"], "sense arrossegar cap finestra")
        editor.comencaArrossegamentDeFinestra()
        editor.reordena([0], a: 2)
        #expect(titols(editor)[0] == ["p11", "p12", "p13"], "arrossegant una finestra, les pestanyes no es mouen")
        #expect(!editor.potObrirArrossegant(id(2)))
        editor.comencaArrossegament(id(11))
        editor.reordenaFinestres([0], a: 2)
        #expect(editor.configuracio.finestres.map(\.nom) == ["a", "b"], "un arrossegament de pestanyes treu la marca")
        editor.reordena([0], a: 2)
        #expect(titols(editor)[0] == ["p12", "p11", "p13"])
        // La marca només val per a un moviment.
        editor.comencaArrossegamentDeFinestra()
        editor.reordenaFinestres([0], a: 2)
        #expect(editor.configuracio.finestres.map(\.nom) == ["b", "a"])
        editor.reordenaFinestres([0], a: 2)
        #expect(editor.configuracio.finestres.map(\.nom) == ["b", "a"])
        #expect(!Editor(senseCarpeta: "prova").potMoureFinestra(id(1), amunt: false))
    }

    /// «Mou amunt» i «Mou avall»: no surten a la primera ni a l'última; un pas de Desfés.
    @Test func mouAmuntIAvall() throws {
        let tmp = try Temporal()
        let editor = try editorAmbQuatre(tmp)
        #expect(!editor.potMoureFinestra(id(1), amunt: true))
        #expect(editor.potMoureFinestra(id(1), amunt: false))
        #expect(!editor.potMoureFinestra(id(4), amunt: false))
        #expect(!editor.potMoureFinestra(id(99), amunt: true))
        editor.mouFinestra(id(2), amunt: false)
        #expect(noms(editor) == ["a", "c", "b", "d"])
        editor.mouFinestra(id(2), amunt: true)
        editor.mouFinestra(id(2), amunt: true)
        #expect(noms(editor) == ["b", "a", "c", "d"])
        editor.mouFinestra(id(2), amunt: true)
        #expect(noms(editor) == ["b", "a", "c", "d"], "ja és la primera")
        #expect(editor.undoManager.undoActionName == "Mou la finestra")
        editor.undoManager.undo()
        #expect(noms(editor) == ["a", "b", "c", "d"])
    }

    /// Reordenar no canvia la llista que es veu («Per revisar») ni les pestanyes triades, i unes posicions fora de rang
    /// no petan: els orígens que no hi són s'ignoren i el destí s'ajusta a la llista.
    @Test func perRevisarISeleccioNoCanvien() throws {
        let tmp = try Temporal()
        let editor = try editorAmbAvisos(tmp)
        editor.lateral = .perRevisar
        editor.pestanyesSeleccionades = [id(21)]
        editor.comencaArrossegamentDeFinestra()
        editor.reordenaFinestres([1], a: 0)
        #expect(noms(editor) == ["b", "a"])
        #expect(editor.lateral == .perRevisar)
        #expect(editor.pestanyesSeleccionades == [id(21)])
        #expect(editor.perRevisarPerFinestra.map(\.finestra.nom) == ["b", "a"])
        editor.undoManager.undo()
        #expect(noms(editor) == ["a", "b"])
        #expect(editor.lateral == .perRevisar)
        #expect(editor.pestanyesSeleccionades == [id(21)])
        editor.comencaArrossegamentDeFinestra()
        editor.reordenaFinestres([0, 7], a: 99)
        #expect(noms(editor) == ["b", "a"], "l'origen 7 no hi és; el destí 99 és el final")
        editor.mouFinestres([id(2)], a: -3)
        #expect(noms(editor) == ["b", "a"], "un destí negatiu és el principi")
        editor.mouFinestres([id(1)], a: -3)
        #expect(noms(editor) == ["a", "b"])
    }

    /// Un nom a mig escriure va al mateix pas que el moviment.
    @Test func ambUnNomAMigEscriure() throws {
        let tmp = try Temporal()
        let editor = try editorAmbQuatre(tmp)
        editor.comencaNom(.finestra(id(3)))
        editor.textDelNom = "Botiga"
        editor.mouFinestra(id(3), amunt: true)
        #expect(noms(editor) == ["a", "Botiga", "b", "d"])
        editor.undoManager.undo()
        #expect(noms(editor) == ["a", "b", "c", "d"])
        #expect(!editor.undoManager.canUndo)
    }
}

// MARK: - Les dades que no arriben (prova 7b)

/// A la fila d'una finestra, la càrrega de les dades arrossegades es cancel·la (-1000/3072) i l'acció arriba amb 0
/// pestanyes: es mouen les de l'última pulsació, fixades en passar per la fila, només si no hi ha cap dubte.
@MainActor
@Suite struct DadesQueNoArribenTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// Una pulsació: SwiftUI demana el proveïdor de la fila premuda i de cada fila arrossegada, en pocs ms.
    private func arrossega(_ editor: Editor, _ ns: [Int], a temps: TimeInterval) {
        for (k, n) in ns.enumerated() { editor.comencaArrossegament(id(n), ara: t0 + temps + Double(k) * 0.001) }
    }

    /// Es mouen al final de «b», en un sol pas, i no en queden de fixades.
    @Test func esMouenLesFixades() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(11), id(13)]
        arrossega(editor, [13, 11, 13], a: 0)
        #expect(editor.pestanyesArrossegades == [id(11), id(13)])
        editor.fixaPestanyesArrossegades()
        #expect(editor.deixaAnar([], a: id(2), local: true, elements: 2))
        #expect(titols(editor) == [["p12"], ["p21", "p22", "p11", "p13"]])
        #expect(editor.pestanyesFixades.isEmpty)
        #expect(editor.undoManager.undoActionName == "Mou les pestanyes")
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 2), "ja no en queden de fixades")
    }

    /// ⇧ dins d'una selecció de 3: AppKit en retalla la selecció i n'arrossega 2, abans que SwiftUI actualitzi la
    /// selecció. Es mouen les 2 de les crides del proveïdor, no les 3 triades.
    @Test func lesDelProveidorINoLaSeleccio() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(11), id(12), id(13)]
        arrossega(editor, [12, 11, 12], a: 0)
        editor.fixaPestanyesArrossegades()
        #expect(editor.deixaAnar([], a: id(2), local: true, elements: 2))
        #expect(titols(editor) == [["p13"], ["p21", "p22", "p11", "p12"]])
    }

    /// Una pulsació nova (un clic, més tard) torna a començar; un clic després de passar per la fila no canvia les
    /// fixades (l'acció arriba ~0,3 s després de deixar anar).
    @Test func unClicDespresNoLesCanvia() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        arrossega(editor, [11], a: 0)
        arrossega(editor, [12, 12], a: 1)
        #expect(editor.pestanyesArrossegades == [id(12)])
        editor.fixaPestanyesArrossegades()
        arrossega(editor, [13], a: 2)
        #expect(editor.deixaAnar([], a: id(2), local: true, elements: 1))
        #expect(titols(editor) == [["p11", "p13"], ["p21", "p22", "p12"]])
    }

    /// No es mou res: si l'arrossegament no és d'aquesta app, si en porta un altre nombre, si no se n'ha fixat cap,
    /// si s'arrossega una finestra, si n'arriben d'una altra execució, si ja no hi són, o a la fila que es veu.
    @Test func quanNoEsMouRes() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        let original = titols(editor)
        func prepara(_ ns: [Int], a temps: TimeInterval) {
            arrossega(editor, ns, a: temps)
            editor.fixaPestanyesArrossegades()
        }
        prepara([11], a: 0)
        #expect(!editor.deixaAnar([], a: id(2), local: false, elements: 1), "d'una altra app o execució")
        prepara([11], a: 1)
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 2), "en porta més")
        prepara([11], a: 2)
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 0), "en porta menys")
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 0), "cap de fixada")
        prepara([11], a: 3)
        #expect(!editor.deixaAnar([], a: id(2)), "sense dir d'on ve")
        arrossega(editor, [11], a: 4)
        editor.comencaArrossegamentDeFinestra()
        editor.fixaPestanyesArrossegades()
        #expect(editor.pestanyesFixades.isEmpty)
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 0), "arrossegant una finestra")
        prepara([11], a: 5)
        let deFora = try #require(PestanyaArrossegada(dades: PortaRetalls.dades([pestanya(12)])))
        #expect(!editor.deixaAnar([deFora], a: id(2), local: true, elements: 1), "d'una altra execució: no les fixades")
        prepara([11], a: 6)
        #expect(!editor.deixaAnar([], a: id(1), local: true, elements: 1), "a la fila de la finestra que es veu")
        #expect(titols(editor) == original)
        #expect(!editor.undoManager.canUndo)
        editor.pestanyesSeleccionades = [id(13)]
        prepara([13], a: 7)
        editor.eliminaPestanyes()
        editor.undoManager.removeAllActions()
        #expect(!editor.deixaAnar([], a: id(2), local: true, elements: 1), "ja no hi és")
        #expect(titols(editor) == [["p11", "p12"], ["p21", "p22"]])
        #expect(!editor.undoManager.canUndo)
    }

    /// A la llista no es fan servir: l'acció no diu d'on ve l'arrossegament.
    @Test func aLaLlistaNo() throws {
        let tmp = try Temporal()
        let editor = try editorAmbDues(tmp)
        editor.pestanyesSeleccionades = [id(13)]
        arrossega(editor, [13], a: 0)
        editor.obreArrossegant(id(2))
        editor.fixaPestanyesArrossegades()
        #expect(!editor.deixaAnar([], a: id(2), index: 0))
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21", "p22"]])
    }

    /// El focus torna a la llista quan hi arriben pestanyes (la llista és nova): a la llista o a la fila de la finestra
    /// oberta arrossegant. No, si van a una altra finestra o no es mou res.
    @Test func elFocusTornaALaLlista() throws {
        for aLaLlista in [true, false] {
            let tmp = try Temporal()
            let editor = try editorAmbDues(tmp)
            editor.pestanyesSeleccionades = [id(13)]
            editor.comencaArrossegament(id(11))
            #expect(editor.deixaAnar(try arrossegades([11]), a: id(2)))
            #expect(editor.lateral == .finestra(id(1)), "no era triada: l'editor no la segueix")
            #expect(editor.demanaFocusLlista == 0, "a una altra finestra")
            #expect(!editor.deixaAnar(try arrossegades([12]), a: id(1)))
            #expect(editor.demanaFocusLlista == 0, "no es mou res")
            editor.pestanyesSeleccionades = [id(12)]
            editor.obreArrossegant(id(2))
            if aLaLlista {
                #expect(editor.deixaAnar(try arrossegades([12]), a: id(2), index: 0))
            } else {
                #expect(editor.deixaAnar(try arrossegades([12]), a: id(2)))
            }
            #expect(editor.demanaFocusLlista == 1, "a la llista: \(aLaLlista)")
        }
    }
}

// MARK: - El Desfés de la plantilla (pas 11)

/// La plantilla té el seu Desfés (el de la finestra de Configuració), i el de l'editor només desfà finestres: si no,
/// ⌘Z a l'editor tornaria a posar una plantilla vella sense que es vegi, i ⌘Z a la Configuració desfaria finestres.
@MainActor
@Suite struct PlantillaDesferTests {
    private func noSalta(_ editor: Editor) {
        editor.canviaPlantilla(nom: "No saltis els permisos") { $0.saltaPermisos = false }
    }

    @Test func laPlantillaVaAlSeuDesfer() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        noSalta(editor)
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.desferPlantilla.undoActionName == "No saltis els permisos")
        #expect(!editor.undoManager.canUndo, "res al Desfés de l'editor")
        #expect(editor.desaSiCal())
        #expect(try !#require(try tmp.magatzem.carrega()).configuracio.plantilla.saltaPermisos)
        editor.desferPlantilla.undo()
        #expect(editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.desferPlantilla.redoActionName == "No saltis els permisos")
        editor.desferPlantilla.redo()
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.canvisSenseDesar)
    }

    /// Un canvi de finestra, després la plantilla, i ⌘Z i ⇧⌘Z a l'editor: la plantilla no torna enrere (ni al fitxer).
    @Test func elDesferDeLEditorNoTocaLaPlantilla() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.reanomenaFinestra(id(1), a: "feina")
        noSalta(editor)
        editor.undoManager.undo()
        #expect(editor.configuracio.finestres[0].nom == "a")
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        editor.undoManager.redo()
        #expect(editor.configuracio.finestres[0].nom == "feina")
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.desaSiCal())
        #expect(try !#require(try tmp.magatzem.carrega()).configuracio.plantilla.saltaPermisos)
    }

    /// I al revés: ⌘Z a la Configuració no toca les finestres, la selecció ni el Desfés de l'editor.
    @Test func elDesferDeLaPlantillaNoTocaLEditor() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        noSalta(editor)
        editor.reanomenaFinestra(id(1), a: "feina")
        editor.lateral = .finestra(id(2))
        editor.pestanyesSeleccionades = [id(21)]
        editor.desferPlantilla.undo()
        #expect(editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.configuracio.finestres[0].nom == "feina")
        #expect(editor.lateral == .finestra(id(2)))
        #expect(editor.pestanyesSeleccionades == [id(21)])
        #expect(editor.undoManager.undoActionName == "Canvia el nom")
    }

    @Test func desferTornarAImportarNoTocaLaPlantilla() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let importacio = editor.previsualitza(lecturaDUnaPestanya())
        noSalta(editor)
        editor.substitueix(amb: importacio)
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        editor.undoManager.undo()
        #expect(editor.configuracio.finestres.map(\.nom) == ["a", "b"])
        #expect(!editor.configuracio.plantilla.saltaPermisos)
    }

    /// Un camp de text de l'inspector que torna a com era treu el seu pas; un canvi de plantilla al mig es queda.
    @Test func unPasAgrupatAmbUnCanviDePlantillaAlMig() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = "o" }
        noSalta(editor)
        editor.canviaClaude([id(11)], nom: "Canvia el model", agrupa: "model") { $0.model = nil }
        #expect(!editor.undoManager.canUndo, "el camp torna a com era: no queda cap pas")
        #expect(!editor.configuracio.plantilla.saltaPermisos)
        #expect(editor.desferPlantilla.canUndo)
    }

    @Test func carregarBuidaElsDosDesfer() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.reanomenaFinestra(id(1), a: "feina")
        noSalta(editor)
        editor.carrega()
        #expect(!editor.undoManager.canUndo)
        #expect(!editor.desferPlantilla.canUndo)
    }

    @Test func senseCanviNiSensePoderEditarNoHiHaPas() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.canviaPlantilla(nom: "Res") { $0.saltaPermisos = true }
        #expect(!editor.desferPlantilla.canUndo)
        // Normalitzada: un model de només espais és cap model.
        editor.canviaPlantilla(nom: "Res") { $0.model = "  " }
        #expect(!editor.desferPlantilla.canUndo)
        #expect(!editor.canvisSenseDesar)
        let sense = Editor(senseCarpeta: "prova")
        sense.canviaPlantilla(nom: "Res") { $0.saltaPermisos = false }
        #expect(!sense.desferPlantilla.canUndo)
        let senseFitxer = try Temporal()
        let buida = Editor(magatzem: senseFitxer.magatzem, retardDesat: nil)
        buida.carrega()
        buida.canviaPlantilla(nom: "Res") { $0.saltaPermisos = false }
        #expect(!buida.desferPlantilla.canUndo)
    }

    /// El de la finestra de Configuració: s'adopta, buida l'anterior i no accepta mai el de l'editor (ni a l'inrevés).
    @Test func elsDosDesferNoEsBarregen() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        noSalta(editor)
        let propi = editor.desferPlantilla
        let deLaConfiguracio = UndoManager()
        editor.usaDesferPlantilla(deLaConfiguracio)
        #expect(editor.desferPlantilla === deLaConfiguracio)
        #expect(!propi.canUndo)
        editor.usaDesferPlantilla(editor.undoManager)
        #expect(editor.desferPlantilla === deLaConfiguracio)
        editor.usaUndoManager(deLaConfiguracio)
        #expect(editor.undoManager !== deLaConfiguracio)
        // Amb el de la finestra (agrupa per esdeveniment), també.
        editor.canviaPlantilla(nom: "Salta els permisos") { $0.saltaPermisos = true }
        #expect(deLaConfiguracio.undoActionName == "Salta els permisos")
        deLaConfiguracio.undo()
        #expect(!editor.configuracio.plantilla.saltaPermisos)
    }

    /// Una pestanya nova fa servir la plantilla d'ara; desfer després la plantilla no la canvia.
    @Test func unaPestanyaNovaAmbLaPlantillaDAra() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        noSalta(editor)
        editor.afegeixPestanya(carpeta: "\(inici)/GitHub/nova")
        let nova = try #require(editor.configuracio.finestres[0].pestanyes.last)
        #expect(!nova.claude.saltaPermisos)
        editor.desferPlantilla.undo()
        #expect(editor.configuracio.finestres[0].pestanyes.last?.claude.saltaPermisos == false)
    }
}

// MARK: - La plantilla a la Configuració (pas 11)

@MainActor
@Suite struct PlantillaConfiguracioTests {
    /// Els camps es llegeixen i es canvien sobre la plantilla, amb el nom del pas de cada camp.
    @Test func elsCampsDeLaPlantilla() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.potCanviarPlantilla)
        #expect(editor.triaPlantilla(.esforc) == .valor("xhigh"))
        #expect(editor.triaPlantilla(.model) == .perDefecte)
        #expect(editor.siNoPlantilla(.saltaPermisos))
        #expect(editor.modeSenseEfectePlantilla)
        editor.triaPlantilla(.esforc, a: .valor("max"))
        #expect(editor.configuracio.plantilla.esforc == "max")
        #expect(editor.desferPlantilla.undoActionName == "Canvia l'esforç")
        editor.posaPlantilla(.saltaPermisos, false)
        #expect(editor.desferPlantilla.undoActionName == "No saltis els permisos")
        #expect(!editor.modeSenseEfectePlantilla)
        editor.triaPlantilla(.modePermisos, a: .valor("plan"))
        editor.triaPlantilla(.model, a: .diversos)
        #expect(editor.desferPlantilla.undoActionName == "Canvia el mode de permisos", "«Valors diversos» no fa res")
        editor.triaPlantilla(.modePermisos, a: .perDefecte)
        #expect(editor.configuracio.plantilla.modePermisos == nil)
        #expect(!editor.undoManager.canUndo)
        // Les pestanyes no canvien.
        #expect(editor.configuracio.finestres == (try #require(try tmp.magatzem.carrega())).configuracio.finestres)
    }

    /// Un valor que Claude no coneix es pot veure (si no, el desplegable no el mostraria).
    @Test func unValorDesconegut() throws {
        let tmp = try Temporal()
        try tmp.magatzem.desa(Configuracio(plantilla: ClaudePestanya(esforc: "extrem", modePermisos: "yolo"),
                                           finestres: []), sobre: nil)
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        editor.carrega()
        #expect(editor.opcionsPlantilla(.esforc).contains { $0.text == "extrem (desconegut)" })
        #expect(editor.opcionsPlantilla(.modePermisos).contains { $0.tria == .valor("yolo") })
        #expect(!editor.opcionsPlantilla(.esforc).contains { $0.tria == .diversos })
        #expect(editor.avisosPlantilla.map(\.tipus) == [.esforcDesconegut("extrem"), .modePermisosDesconegut("yolo")])
    }

    /// Els avisos no porten el de l'ordre (el diu el bloc de l'ordre); amb Claude apagat, cap.
    @Test func elsAvisosDeLaPlantilla() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.avisosPlantilla.map(\.tipus) == [.ultracode])
        editor.canviaPlantilla(nom: "settings") { $0.esforc = "high"; $0.settings = "/Users/prova/s.json" }
        #expect(!editor.avisosPlantilla.contains { if case .ordreImpossible = $0.tipus { true } else { false } })
        editor.posaPlantilla(.activat, false)
        #expect(editor.avisosPlantilla.isEmpty)
    }

    /// El nom fix de sessió de la plantilla (escrit a mà) es mostra a part: no s'aplica.
    @Test func elNomDeSessioEsMostraAPart() throws {
        let tmp = try Temporal()
        var plantilla = ClaudePestanya.habituals
        plantilla.nom = "feina"
        try tmp.magatzem.desa(Configuracio(plantilla: plantilla, finestres: [Finestra(id: id(1), nom: "a")]), sobre: nil)
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil, carpetaExisteix: { _ in true }, nouId: Ids().nou)
        editor.carrega()
        #expect(editor.nomSessioPlantilla == "feina")
        editor.afegeixPestanya(carpeta: "\(inici)/GitHub/nova")
        let nova = try #require(editor.configuracio.finestres[0].pestanyes.last)
        #expect(nova.claude.nom == nil)
        // L'ordre de la Configuració és la que rebrà la pestanya nova: sense `--name` (revisió del pas 11).
        let perANova = try #require(editor.plantillaPerAPestanyaNova)
        let ordre = try #require(try OrdreClaude.text(de: perANova, repren: nil).get())
        #expect(!ordre.contains("--name"))
        #expect(ordre == (try OrdreClaude.text(de: nova.claude, repren: nil).get()))
    }

    /// Per què no es pot canviar, en cada estat.
    @Test func quanNoEsPotCanviar() throws {
        let tmp = try Temporal()
        let buida = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        #expect(buida.motiuPlantillaNoEditable == "Es llegeix la configuració…")
        #expect(buida.plantillaVisible == nil)
        buida.carrega()
        #expect(!buida.potCanviarPlantilla)
        #expect(buida.plantillaVisible == .perOmissio)
        #expect(buida.plantillaVisible == buida.plantillaPerImportar)
        // Les importades que no tenien Claude obert queden només terminal (D-P5a): el text no diu que s'hi obrirà
        // «claude» (revisió de la 0.29.1).
        #expect(buida.motiuPlantillaNoEditable == "Encara no hi ha cap configuració. Si importes de Warp, les pestanyes "
            + "que no tenien Claude obert queden només terminal. Les pestanyes que afegeixis, i aquestes si hi actives "
            + "Claude, s'obriran amb «claude».")
        let sense = Editor(senseCarpeta: "la carpeta no existeix")
        sense.carrega()
        #expect(sense.motiuPlantillaNoEditable?.hasPrefix("No es pot canviar: ") == true)

        // Amb el fitxer malmès no se sap quina és la plantilla: no se'n mostra cap (revisió del pas 11).
        let malmes = try Temporal()
        let m = malmes.magatzem
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: m.fitxer)
        let ambError = Editor(magatzem: m, retardDesat: nil)
        ambError.carrega()
        #expect(ambError.plantillaVisible == nil && ambError.plantillaPerAPestanyaNova == nil)
        #expect(ambError.avisosPlantilla.isEmpty && ambError.opcionsNomesLecturaPlantilla.isEmpty)
        #expect(ambError.nomSessioPlantilla == nil)
        #expect(ambError.motiuPlantillaNoEditable?.hasPrefix("No es pot canviar: ") == true)
        let tmp2 = try Temporal()
        let editor = try editorAmbMostra(tmp2)
        #expect(editor.motiuPlantillaNoEditable == nil)
    }

    /// L'inspector dona el mateix que abans per a les pestanyes triades.
    @Test func lInspectorNoCanvia() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = []
        #expect(editor.tria(.esforc) == .perDefecte)
        editor.canviaClaude([id(11)], nom: "x") { $0.esforc = "max" }
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(editor.tria(.esforc) == .diversos)
        #expect(editor.opcions(.esforc).first?.tria == .diversos)
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.tria(.esforc) == .valor("max"))
    }
}

// MARK: - Pas 11: ordres de la barra de menús i menú de la icona

@MainActor
@Suite struct OrdresMenuTests {
    /// Duplica i «Canvia el nom» segons la columna amb el focus: sense focus, res.
    @Test func duplicaICanviaElNomSegonsLaColumna() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        #expect(editor.objecte(nil) == nil)
        #expect(editor.titolDuplica(nil) == "Duplica")
        #expect(!editor.potCanviarElNom(nil))

        editor.pestanyesSeleccionades = []
        #expect(editor.objecte(.llista) == nil, "cap pestanya triada")
        #expect(editor.titolDuplica(.llista) == "Duplica")
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.objecte(.llista) == .pestanyes([id(11)]))
        #expect(editor.titolDuplica(.llista) == "Duplica la pestanya")
        #expect(editor.potCanviarElNom(.llista))
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(editor.titolDuplica(.llista) == "Duplica les pestanyes")
        #expect(!editor.potCanviarElNom(.llista), "només una")
        editor.canviaElNom(.llista)
        #expect(editor.nomEnEdicio == nil)

        #expect(editor.objecte(.barraLateral) == .finestra(id(1)))
        #expect(editor.titolDuplica(.barraLateral) == "Duplica la finestra")
        #expect(editor.potCanviarElNom(.barraLateral))
        editor.canviaElNom(.barraLateral)
        #expect(editor.nomEnEdicio == .finestra(id(1)))
        editor.acabaNom(.finestra(id(1)), desant: false)

        editor.duplica(.barraLateral)
        #expect(editor.configuracio.finestres.count == 3)
        #expect(editor.undoManager.undoActionName == "Duplica la finestra")
        editor.undoManager.undo()

        editor.pestanyesSeleccionades = [id(12)]
        editor.duplica(.llista)
        #expect(editor.undoManager.undoActionName == "Duplica la pestanya")
        #expect(editor.configuracio.finestres[0].pestanyes.count == 4)
        editor.undoManager.undo()

        editor.pestanyesSeleccionades = [id(13)]
        editor.canviaElNom(.llista)
        #expect(editor.nomEnEdicio == .pestanya(id(13)))
        editor.acabaNom(.pestanya(id(13)), desant: false)

        // «Per revisar» no és una finestra: ni Duplica ni «Canvia el nom» a la barra lateral.
        editor.lateral = .perRevisar
        #expect(editor.objecte(.barraLateral) == nil)
        #expect(!editor.potCanviarElNom(.barraLateral))
    }

    /// Amb el full d'importació o el diàleg de carpetes oberts, o sense poder editar, cap ordre canvia res.
    @Test func ambUnFullObertNoHiHaOrdres() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        #expect(editor.ordresActives && editor.potNovaPestanya && editor.potImportar)
        #expect(editor.potMoureTriades && editor.potDesactivarClaude)

        for full in [\Editor.demanaImportacio, \Editor.demanaNovaPestanya] {
            editor[keyPath: full] = true
            #expect(!editor.ordresActives)
            #expect(editor.objecte(.llista) == nil && editor.objecte(.barraLateral) == nil)
            #expect(!editor.potNovaPestanya && !editor.potImportar && !editor.potMoureTriades)
            #expect(!editor.potActivarClaude && !editor.potDesactivarClaude)
            editor.duplica(.llista)
            editor.activaClaudeTriades(false)
            #expect(!editor.undoManager.canUndo)
            editor[keyPath: full] = false
        }

        let sense = Editor(senseCarpeta: "argument desconegut «--confg»")
        sense.carrega()
        #expect(!sense.ordresActives && !sense.potImportar && !sense.potNovaPestanya)
        #expect(!sense.potEliminarFinestra && !sense.potEliminarPestanyes)
        #expect(sense.fitxerPerMostrar == nil)
    }

    /// Importa de Warp…: amb configuració o sense, però no carregant ni amb error.
    @Test func quanEsPotImportar() throws {
        let tmp = try Temporal()
        let editor = Editor(magatzem: tmp.magatzem, retardDesat: nil)
        #expect(editor.estat == .carregant)
        #expect(!editor.potImportar)
        editor.carrega()
        #expect(editor.estat == .senseConfiguracio)
        #expect(editor.potImportar)
        #expect(!editor.ordresActives)

        let malmes = try Temporal()
        let m = malmes.magatzem
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: m.fitxer)
        let ambError = Editor(magatzem: m, retardDesat: nil)
        ambError.carrega()
        #expect(!ambError.potImportar)
        // Mostra el fitxer al Finder sí, per poder-lo arreglar.
        #expect(ambError.fitxerPerMostrar?.path == m.fitxer.path)
    }

    /// ⌘D amb un nom a mig escriure: el nom i la còpia són un sol pas, i la còpia porta el nom nou.
    @Test func duplicarAmbUnNomAMigEscriureEsUnSolPas() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = [id(11)]
        editor.comencaNom(.pestanya(id(11)))
        editor.textDelNom = "Botiga"
        editor.duplica(.llista)
        #expect(editor.nomEnEdicio == nil)
        #expect(editor.configuracio.finestres[0].pestanyes.map(\.titol) == ["Botiga", "Botiga", "p12", "p13"])
        editor.undoManager.undo()
        #expect(titols(editor) == [["p11", "p12", "p13"], ["p21"]])
        #expect(!editor.undoManager.canUndo)

        editor.comencaNom(.finestra(id(2)))
        editor.textDelNom = "feina"
        editor.duplicaFinestra(id(2))
        #expect(editor.configuracio.finestra(id(2))?.nom == "feina")
        #expect(editor.configuracio.finestres.count == 3)
        editor.undoManager.undo()
        #expect(editor.configuracio.finestra(id(2))?.nom == "b")
        #expect(editor.configuracio.finestres.count == 2)
        #expect(!editor.undoManager.canUndo)
    }

    /// Amb pestanyes amb Claude i sense, totes dues ordres s'apliquen a totes les triades.
    @Test func activaIDesactivaAmbSeleccioMixta() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.activaClaude([id(11)], false)
        editor.pestanyesSeleccionades = [id(11), id(12)]
        #expect(editor.potActivarClaude && editor.potDesactivarClaude)
        editor.activaClaudeTriades(true)
        #expect(editor.undoManager.undoActionName == "Activa Claude")
        #expect(editor.configuracio.pestanya(id(11))?.claude.activat == true)
        #expect(!editor.potActivarClaude && editor.potDesactivarClaude)
        editor.activaClaudeTriades(true)
        #expect(editor.undoManager.undoActionName == "Activa Claude")
        editor.activaClaudeTriades(false)
        #expect(editor.undoManager.undoActionName == "Desactiva Claude")
        #expect(editor.configuracio.pestanya(id(12))?.claude.activat == false)
        #expect(editor.potActivarClaude && !editor.potDesactivarClaude)
    }

    /// Edició › Elimina, desactivat si no hi ha res a eliminar.
    @Test func eliminaNomesAmbAlgunaCosaTriada() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.pestanyesSeleccionades = []
        #expect(!editor.potEliminarPestanyes)
        #expect(editor.potEliminarFinestra)
        editor.pestanyesSeleccionades = [id(12)]
        #expect(editor.potEliminarPestanyes)
        editor.lateral = .perRevisar
        #expect(!editor.potEliminarFinestra)
    }

    /// «Nova pestanya…» obre el diàleg de carpetes només si s'hi pot afegir una pestanya.
    @Test func novaPestanyaObreElDialeg() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        editor.demanaImportacio = true
        editor.demanaPestanyaNova()
        #expect(!editor.demanaNovaPestanya, "amb el full d'importació obert")
        editor.demanaImportacio = false
        editor.lateral = .perRevisar
        editor.demanaPestanyaNova()
        #expect(!editor.demanaNovaPestanya, "a «Per revisar»")
        editor.lateral = .finestra(id(2))
        editor.demanaPestanyaNova()
        #expect(editor.demanaNovaPestanya)
        #expect(!editor.potNovaPestanya, "ja és obert")
    }

    /// Mostra el fitxer al Finder: el fitxer, si no la carpeta, si no res.
    @Test func elFitxerPerMostrar() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        #expect(editor.fitxerPerMostrar == nil, "no hi ha res")
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        #expect(editor.fitxerPerMostrar?.path == m.carpeta.path)
        editor.comencaEnBlanc()
        #expect(editor.desaSiCal())
        #expect(editor.fitxerPerMostrar?.path == m.fitxer.path)
    }
}

@MainActor
@Suite struct MenuIconaTests {
    @Test func senseAvisos() throws {
        let tmp = try Temporal()
        #expect(try editorAmbMostra(tmp).avisosMenu.isEmpty)
    }

    /// Sense carpeta ja surt «Sense configuració: …»: no cal també «La configuració té errors».
    @Test func senseCarpetaCapAvis() {
        let editor = Editor(senseCarpeta: "argument desconegut «--confg»")
        editor.carrega()
        #expect(editor.avisosMenu.isEmpty)
    }

    @Test func unFitxerMalmes() throws {
        let tmp = try Temporal()
        let m = tmp.magatzem
        try FileManager.default.createDirectory(at: m.carpeta, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: m.fitxer)
        let editor = Editor(magatzem: m, retardDesat: nil)
        editor.carrega()
        #expect(editor.avisosMenu == [.configuracioAmbErrors])
        #expect(Editor.AvisMenu.configuracioAmbErrors.text == "La configuració té errors")
    }

    @Test func elFitxerHaCanviatFora() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        try Configuracio(finestres: [Finestra(id: UUID(), nom: "de fora")]).json().write(to: tmp.magatzem.fitxer)
        editor.afegeixFinestra()
        #expect(!editor.desaSiCal())
        #expect(editor.avisosMenu == [.fitxerCanviatFora])
        #expect(editor.avisosMenu.first?.text == "El fitxer ha canviat fora de l'app")
    }

    @Test func noSHaPogutDesar() throws {
        let tmp = try Temporal()
        let editor = try editorAmbMostra(tmp)
        let m = tmp.magatzem
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: m.fitxer.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: m.fitxer.path) }
        editor.reanomenaFinestra(id(1), a: "feina")
        #expect(!editor.desaSiCal())
        #expect(editor.avisosMenu == [.noSHaPogutDesar])
    }
}
