import Foundation
import Observation
import WarpLaunchCore

/// Els lligams de cada pestanya amb el seu pane i la seva conversa (`estat.json`, fase 3.1). Es posen al dia a cada
/// lectura de Warp: en arrencar, amb «Actualitza l'estat de Warp», abans d'obrir i, mentre l'app és en marxa, cada 60 s (D18).
///
/// Només s'escriu si alguna cosa canvia. Qui el crida ha de vigilar que hi hagi configuració: sense, no s'escriu res.
@MainActor
@Observable
public final class EstatSessions {
    public private(set) var estat = EstatApp()
    /// Per què no es pot fer servir `estat.json` (d'una versió més nova, o no es pot llegir): no s'hi escriu, i l'app
    /// no obrirà res fins que s'arregli.
    public private(set) var bloqueig: String?
    /// L'últim desat ha fallat (es torna a provar al següent canvi). L'estat de la memòria sí que està al dia.
    public private(set) var errorDesar: String?
    /// Les converses amb un Claude viu, de l'última lectura de Warp.
    private var vives: Set<String> = []

    /// La carpeta de Warp de cada pane, de l'última lectura amb la foto o de la importació (l'avís de «Per revisar»). Només a la
    /// memòria: el format d'`estat.json` no canvia, i després d'un reinici només queda el que diu `carpetaSessio`.
    @ObservationIgnored private var carpetesWarp: [String: String] = [:]
    /// Quan pot haver canviat l'avís de «Per revisar» d'alguna pestanya (`Editor.refrescaAvisos`).
    @ObservationIgnored public var enCanviar: @MainActor () -> Void = {}

    /// Les converses recents de cada carpeta, fins a la pròxima lectura de Warp: l'inspector les demana a cada redibuix, i
    /// llegir-les pot trigar 60 ms (05/11/2026). En obrir, el pla les torna a llegir.
    @ObservationIgnored private var recents: [String: [LectorTranscripcions.Recent]] = [:]

    @ObservationIgnored private let magatzem: MagatzemEstat?
    /// La carpeta de la configuració, si l'app en té.
    public var carpeta: URL? { magatzem?.carpeta }
    @ObservationIgnored private let rellotge: () -> Date
    @ObservationIgnored private var carregat = false

    /// - Parameter magatzem: `nil` si l'app no té carpeta: llavors no es llegeix ni s'escriu res.
    public init(magatzem: MagatzemEstat?, rellotge: @escaping () -> Date = { Date() }) {
        self.magatzem = magatzem
        self.rellotge = rellotge
    }

    /// Llegeix `estat.json`. Sense fitxer, l'estat és buit.
    public func carrega() {
        guard let magatzem else { return }
        do {
            estat = try magatzem.carrega()
            bloqueig = nil
            carregat = true
        } catch {
            bloqueig = error.description
            carregat = false
        }
        enCanviar()
    }

    /// L'avís de la carpeta de Claude d'una pestanya, si n'hi ha (`Validacio.avisCarpetaDeClaude`).
    public func avisCarpeta(_ pestanya: Pestanya, inici: String, carpetaExisteix: (String) -> Bool) -> Avis? {
        let vincle = estat.pestanyes[pestanya.id]
        return Validacio.avisCarpetaDeClaude(pestanya, vincle: vincle, carpetaWarp: vincle?.pane.flatMap { carpetesWarp[$0] },
                                             inici: inici, carpetaExisteix: carpetaExisteix)
    }

    /// La conversa que reprendria la pestanya, si se sap.
    public func conversa(de pestanya: UUID) -> String? {
        estat.conversa(de: pestanya)
    }

    /// La conversa que reprendria la pestanya, per a l'inspector i «Copia l'ordre» (`EstatApp.conversaAReprendre`).
    public func conversaAReprendre(_ pestanya: Pestanya, transcripcions: LectorTranscripcions) -> String? {
        let carpeta = Rutes.canonica(pestanya.carpeta)
        let llista = recents[carpeta] ?? transcripcions.recents(carpeta: carpeta)
        recents[carpeta] = llista
        return estat.conversaAReprendre(de: pestanya.id, recents: llista, vives: vives)
    }

    /// Posa al dia els lligams amb una lectura de Warp.
    public func actualitza(amb lectura: LecturaWarp, configuracio: Configuracio) {
        if vives != lectura.conversesVives { vives = lectura.conversesVives }
        recents = [:]
        // Les lectures de cada minut no porten les finestres: la foto es queda fins a la pròxima.
        let foto = Self.carpetesDeWarp(lectura, abans: carpetesWarp)
        let fotoNova = foto != carpetesWarp
        carpetesWarp = foto
        let abans = estat
        desa(ActualitzaEstat.amb(lectura, configuracio: configuracio, estat: estat, ara: rellotge()))
        if fotoNova, estat == abans { enCanviar() }
    }

    /// Els lligams d'una importació (en crear la configuració o tornar a importar).
    public func vincula(_ vincles: [UUID: VincleImportat]) {
        guard !vincles.isEmpty else { return }
        let abans = estat
        for vincle in vincles.values { carpetesWarp[vincle.pane] = vincle.carpetaWarp }
        desa(ActualitzaEstat.vincula(vincles, estat: estat, ara: rellotge()))
        if estat == abans { enCanviar() }
    }

    /// «Lliga amb Warp…» (`ActualitzaEstat.lliga`). Torna l'error si no s'ha pogut desar.
    @discardableResult
    public func lligaAmbWarp(_ vincles: [UUID: VincleImportat]) -> String? {
        guard !vincles.isEmpty else { return nil }
        return desa(ActualitzaEstat.lliga(vincles, estat: estat, ara: rellotge()))
    }

    /// Per què no es pot obrir res ara (fase 3.1): sense `estat.json` no se sabria què ja és obert, ni es podria
    /// recordar el llançament.
    public var motiuNoEsPotObrir: String? {
        if let bloqueig { return "«estat.json» no es pot fer servir: \(bloqueig)" }
        guard magatzem != nil, carregat else { return "«estat.json» encara no s'ha llegit" }
        return nil
    }

    /// Desa un llançament (nou o posat al dia). Torna l'error si no s'ha pogut desar: llavors no s'ha d'obrir res, i un
    /// llançament nou no queda ni a la memòria (no s'ha obert res, i no ha d'avisar de res).
    @discardableResult
    public func desa(llancament: Llancament) -> String? {
        let abans = estat
        var nou = estat
        nou.desa(llancament)
        guard let error = desa(nou) else { return nil }
        if !abans.llancaments.contains(where: { $0.id == llancament.id }) { estat = abans }
        return error
    }

    /// El pane de cada pestanya a la finestra que s'acaba d'obrir, i el shell de cada pestanya de terminal (0.34.0).
    public func lliga(panes: [UUID: String], shells: [UUID: ShellRecordat]) {
        guard !panes.isEmpty || !shells.isEmpty else { return }
        desa(ActualitzaEstat.ambPanes(panes, shells: shells, estat: estat, ara: rellotge()))
    }

    /// La carpeta de Warp dels panes on no coincideix amb la del seu Claude, posada al dia amb la foto. Si Claude ja no hi és
    /// (Warp tancat, o ha sortit), no se sap res de nou: el pane conserva la que tenia, llevat que Warp ja en digui una altra.
    private static func carpetesDeWarp(_ lectura: LecturaWarp, abans: [String: String]) -> [String: String] {
        var carpetes = abans
        for pane in lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes) {
            if let claude = pane.claude {
                carpetes[pane.uuid] = claude.carpeta == pane.carpeta ? nil : pane.carpeta
            } else if carpetes[pane.uuid] != pane.carpeta {
                carpetes[pane.uuid] = nil
            }
        }
        return carpetes
    }

    /// Torna l'error, si n'hi ha.
    @discardableResult
    private func desa(_ nou: EstatApp) -> String? {
        if let motiu = motiuNoEsPotObrir { return motiu }
        guard let magatzem, nou != estat || errorDesar != nil else { return nil }
        let canvia = nou != estat
        estat = nou
        defer { if canvia { enCanviar() } }
        do {
            try magatzem.desa(nou)
            errorDesar = nil
            return nil
        } catch {
            if case .escriptura = error { errorDesar = error.description } else { bloqueig = error.description }
            return error.description
        }
    }
}
