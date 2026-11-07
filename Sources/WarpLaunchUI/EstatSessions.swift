import Foundation
import Observation
import WarpLaunchCore

/// Els lligams de cada pestanya amb el seu pane i la seva conversa (`estat.json`, fase 3.1). Es posen al dia a cada
/// lectura de Warp: en arrencar, amb «Torna a llegir», abans d'obrir i, mentre l'app és en marxa, cada 60 s (D18).
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
        desa(ActualitzaEstat.amb(lectura, configuracio: configuracio, estat: estat, ara: rellotge()))
    }

    /// Els lligams d'una importació (en crear la configuració o tornar a importar).
    public func vincula(_ vincles: [UUID: VincleImportat]) {
        guard !vincles.isEmpty else { return }
        desa(ActualitzaEstat.vincula(vincles, estat: estat, ara: rellotge()))
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

    /// El pane de cada pestanya a la finestra que s'acaba d'obrir.
    public func lliga(panes: [UUID: String]) {
        guard !panes.isEmpty else { return }
        desa(ActualitzaEstat.ambPanes(panes, estat: estat, ara: rellotge()))
    }

    /// Torna l'error, si n'hi ha.
    @discardableResult
    private func desa(_ nou: EstatApp) -> String? {
        if let motiu = motiuNoEsPotObrir { return motiu }
        guard let magatzem, nou != estat || errorDesar != nil else { return nil }
        estat = nou
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
