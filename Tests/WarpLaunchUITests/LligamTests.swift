import Foundation
import Testing
@testable import WarpLaunchCore
@testable import WarpLaunchUI

// «Lliga amb Warp…» (0.21.0): el full llegeix Warp, proposa i, només amb «Lliga», desa a `estat.json`. Lectures
// inventades i carpetes temporals.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let t0 = Date(timeIntervalSince1970: 1_793_750_400)
private func pane(_ lletra: Character) -> String { String(repeating: lletra, count: 32) }

/// «W»: A i B. A Warp, A amb el seu Claude i B a la carpeta d'inici (només pel títol).
private let configuracio = Configuracio(plantilla: .habituals, finestres: [
    Finestra(id: id(100), nom: "W", pestanyes: [
        Pestanya(id: id(1), titol: "A", carpeta: "/x/a", claude: .habituals),
        Pestanya(id: id(2), titol: "B", carpeta: "/x/b", claude: .habituals),
    ]),
])

private let warp = LecturaWarp(finestres: [
    FinestraLlegida(numero: 1, pestanyaActiva: 0, pestanyes: [
        PestanyaLlegida(posicio: 0, titol: "A", color: nil, panes: [
            PaneLlegit(uuid: pane("a"), carpeta: "/x/a", origenCarpeta: .pane, carpetaExisteix: true,
                       claude: SessioClaude(pid: 1, sessionId: "s-a", carpeta: "/x/a", iniciada: t0, ordre: ["claude"],
                                            opcions: OpcionsClaude(), paneUUID: pane("a"), dinsDeWarp: true)),
        ]),
        PestanyaLlegida(posicio: 1, titol: "B", color: nil, panes: [
            PaneLlegit(uuid: pane("b"), carpeta: "/Users/prova", origenCarpeta: .pane, carpetaExisteix: true),
        ]),
    ]),
], sessionsSensePestanya: [], avisos: [])

@MainActor
private final class Banc {
    let carpeta: URL
    let editor: Editor
    let sessions: EstatSessions
    var lligam: Lligam!
    var lectura: Result<LecturaWarp, EstatWarp.ErrorLectura> = .success(warp)
    /// Sense refresc, com amb una carpeta de prova (`--config`).
    var ambRefresc = false

    init() throws {
        carpeta = FileManager.default.temporaryDirectory.appending(path: "warp-launch-lligam-\(UUID().uuidString)")
        try MagatzemConfiguracio(carpeta: carpeta, inici: "/Users/prova").desa(configuracio, sobre: nil)
        editor = Editor(magatzem: MagatzemConfiguracio(carpeta: carpeta, inici: "/Users/prova"), retardDesat: nil)
        editor.carrega()
        sessions = EstatSessions(magatzem: MagatzemEstat(carpeta: carpeta), rellotge: { t0 })
        sessions.carrega()
        lligam = Lligam(editor: editor, sessions: sessions, inici: "/Users/prova", llegeix: { [unowned self] in lectura },
                        ambRefresc: { [unowned self] in ambRefresc })
        editor.lligam = lligam
    }

    deinit { try? FileManager.default.removeItem(at: carpeta) }

    var estatAlDisc: EstatApp { (try? MagatzemEstat(carpeta: carpeta).carrega()) ?? EstatApp() }
}

@MainActor
@Suite struct LligamTests {
    @Test func proposaILliga() async throws {
        let b = try Banc()
        #expect(b.editor.potLligar)
        await b.lligam.demana()
        guard case let .llest(proposta) = b.lligam.estat else { Issue.record("\(b.lligam.estat)"); return }
        #expect(proposta.parelles.map { "\($0.pestanya.titol) \($0.criteri)" } == ["A titolICarpeta", "B titol"])
        #expect(!b.editor.potLligar && !b.editor.potObrir(id(100)))
        // Fins a «Lliga», res al disc.
        #expect(b.estatAlDisc.pestanyes.isEmpty)

        b.lligam.desmarcades = [id(2)]
        b.lligam.confirma()
        #expect(b.lligam.estat == .fet(1, error: nil))
        #expect(b.estatAlDisc.pestanyes == [
            id(1): VincleEstat(pane: pane("a"), sessio: "s-a", carpetaSessio: "/x/a", origen: .importacio, vista: t0),
        ])
        b.lligam.cancela()
        #expect(b.editor.potLligar)
    }

    @Test func senseLecturaNoDesaRes() async throws {
        let b = try Banc()
        b.lectura = .failure(EstatWarp.ErrorLectura(description: "sense permís"))
        await b.lligam.demana()
        #expect(b.lligam.estat == .error("sense permís"))
        b.lligam.confirma()
        #expect(!FileManager.default.fileExists(atPath: b.carpeta.appending(path: EstatApp.nomFitxer).path))
    }

    /// Amb la restauració de sessió desactivada, Warp no desa les finestres (0.22.0): no hi ha res amb què lligar. Ho diu, i
    /// no desa res.
    @Test func senseFinestresNoEsPotLligar() async throws {
        let b = try Banc()
        var lectura = warp
        lectura.warpDesaFinestres = false
        b.lectura = .success(lectura)
        await b.lligam.demana()
        guard case let .error(motiu) = b.lligam.estat else { Issue.record("\(b.lligam.estat)"); return }
        #expect(motiu.hasPrefix(LecturaWarp.senseFinestres))
        #expect(motiu.contains("pestanyes amb Claude"), "les que no en tenen no es lliguen soles")
        b.lligam.confirma()
        #expect(!FileManager.default.fileExists(atPath: b.carpeta.appending(path: EstatApp.nomFitxer).path))
    }

    /// Sense refresc (una carpeta de prova, `--config`), l'app no toca l'ajust de Warp i no li pot demanar que desi les
    /// finestres: el full ho diu, amb el mateix text que el d'importar, i que amb la configuració de debò sí que es pot.
    /// Amb el refresc (la configuració de debò), el text de sempre.
    @Test func senseFinestresAmbUnaCarpetaDeProvaDiuPerQue() async throws {
        let b = try Banc()
        var lectura = warp
        lectura.warpDesaFinestres = false
        b.lectura = .success(lectura)
        await b.lligam.demana()
        guard case let .error(motiu) = b.lligam.estat else { Issue.record("\(b.lligam.estat)"); return }
        #expect(motiu == LecturaWarp.senseFinestres + " Amb una configuració de prova (--config), l'app no toca aquest "
            + "ajust i no pot demanar a Warp que les desi. Amb la configuració de debò, sí: l'activa uns segons perquè Warp "
            + "les desi, i el torna a desactivar. Les pestanyes amb Claude que obre l'app es lliguen soles.")
        #expect(motiu.hasPrefix(MotiuSenseFinestres.deProva.text), "el text del full d'importar")

        b.lligam.cancela()
        b.ambRefresc = true
        await b.lligam.demana()
        #expect(b.lligam.estat == .error(LecturaWarp.senseFinestres
            + " Les pestanyes amb Claude que obre l'app es lliguen soles."))
        b.lligam.confirma()
        #expect(!FileManager.default.fileExists(atPath: b.carpeta.appending(path: EstatApp.nomFitxer).path))
    }

    /// Sense cap Warp Stable (0.31.1), la lectura de l'app no té finestres (`Lector.llegeixDeLApp`): el full diu el mateix que
    /// el d'obrir, amb una carpeta de prova i amb la configuració de debò, i no desa res.
    @Test func senseCapWarpDiuElMateixAmbUnaCarpetaDeProvaIAmbLaDeDebo() async throws {
        let b = try Banc()
        var lectura = warp
        lectura.finestres = []
        lectura.warpDesaFinestres = false
        lectura.warpPreview = .capWarp
        b.lectura = .success(lectura)
        for ambRefresc in [false, true] {
            b.ambRefresc = ambRefresc
            await b.lligam.demana()
            #expect(b.lligam.estat == .error("No s'ha trobat Warp en aquest Mac: cal Warp Stable."), "refresc: \(ambRefresc)")
            b.lligam.confirma()
            b.lligam.cancela()
        }
        #expect(!FileManager.default.fileExists(atPath: b.carpeta.appending(path: EstatApp.nomFitxer).path))
    }

    /// Warp Stable instal·lat i que no s'ha obert mai en aquest usuari: no hi ha la base (`warpSenseBase`). El full diu que
    /// Warp encara no hi ha desat res, com el d'importar i el CLI, i no que la restauració és desactivada; amb Warp Stable,
    /// les pestanyes que obre l'app es lliguen soles. Amb una carpeta de prova i amb la configuració de debò. No desa res.
    @Test func senseLaBaseDeWarpDiuQueEncaraNoHiHaDesatRes() async throws {
        let b = try Banc()
        for obert in [false, true] {
            var lectura = warp
            lectura.finestres = []
            lectura.warpDesaFinestres = false
            lectura.warpObert = obert
            lectura.warpSenseBase = true
            b.lectura = .success(lectura)
            for ambRefresc in [false, true] {
                b.ambRefresc = ambRefresc
                await b.lligam.demana()
                #expect(b.lligam.estat == .error(LecturaWarp.senseBase(warpObert: obert)
                    + " Les pestanyes amb Claude que obre l'app es lliguen soles."), "obert: \(obert), refresc: \(ambRefresc)")
                b.lligam.confirma()
                b.lligam.cancela()
            }
        }
        #expect(!FileManager.default.fileExists(atPath: b.carpeta.appending(path: EstatApp.nomFitxer).path))
    }

    /// Amb `estat.json` d'una versió més nova, no es pot lligar (no s'hi escriuria).
    @Test func ambEstatBlocatNoEsPot() async throws {
        let b = try Banc()
        try Data(#"{"versio": 2, "pestanyes": {}, "llancaments": []}"#.utf8)
            .write(to: b.carpeta.appending(path: EstatApp.nomFitxer))
        b.sessions.carrega()
        #expect(!b.editor.potLligar)
        await b.lligam.demana()
        #expect(b.lligam.estat == .cap)
    }
}
