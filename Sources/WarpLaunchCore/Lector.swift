import Foundation

/// Si es llegeix la base de Warp (`warp.sqlite`).
public enum BaseWarp: Sendable {
    /// Segons l'ajust de Warp: si no desa les finestres, la base és d'abans i no es llegeix.
    case segonsAjust
    /// Sempre: és la foto de l'última vegada que Warp va desar (D19). `warpDesaFinestres` surt `true`.
    case sempre
    /// Mai: l'app gestiona l'ajust (`RefrescWarp`), la base només és la foto, i el que hi ha obert ho diuen els processos.
    case mai
}

/// Llegeix Warp i Claude, i lliga cada sessió interactiva amb el pane on corre (fase 1, R1).
/// No escriu res: ni a Warp, ni a `~/.claude`, ni enlloc.
public struct Lector: Sendable {
    public var rutaWarp: URL
    /// `settings.toml` de Warp, per saber si desa les finestres. `nil`: no es mira, i es llegeix la base (`--warp`).
    public var rutaAjustos: URL?
    public var carpetaSessions: URL
    public var processos: any FontProcessos
    /// Carpeta d'inici de l'usuari. Un pane amb aquesta carpeta probablement l'ha perduda en restaurar-se.
    public var inici: String

    public init(rutaWarp: URL = LectorWarp.rutaPerDefecte,
                rutaAjustos: URL? = LectorAjustosWarp.rutaPerDefecte,
                carpetaSessions: URL = LectorSessions.carpetaPerDefecte,
                // Sense valor per defecte: una prova que se l'oblidés llegiria els processos de debò.
                processos: any FontProcessos,
                inici: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.rutaWarp = rutaWarp
        self.rutaAjustos = rutaAjustos
        self.carpetaSessions = carpetaSessions
        self.processos = processos
        self.inici = inici
    }

    public func llegeix(base: BaseWarp = .segonsAjust) throws -> LecturaWarp {
        // Si Warp no desa les finestres, la base és d'abans: ni es llegeix.
        let desaFinestres: Bool? = switch base {
        case .segonsAjust: rutaAjustos.map { LectorAjustosWarp(ruta: $0).desaFinestres() }
        case .sempre: true
        case .mai: false
        }
        let finestresWarp = desaFinestres == false ? [] : try LectorWarp(ruta: rutaWarp).llegeix()
        var (sessions, noInteractives, avisos) = LectorSessions(carpeta: carpetaSessions, processos: processos).llegeixTotes()

        // Sessió de cada pane. Si n'hi ha dues amb el mateix UUID, es queda la més recent.
        var perPane: [String: SessioClaude] = [:]
        for sessio in sessions where sessio.dinsDeWarp {
            guard let uuid = sessio.paneUUID else { continue }
            if let altra = perPane[uuid] {
                let nova = (sessio.iniciada ?? .distantPast) > (altra.iniciada ?? .distantPast) ? sessio : altra
                let vella = nova == sessio ? altra : sessio
                avisos.append("dues sessions al mateix pane \(uuid): es mostra la del pid \(nova.pid), no la del \(vella.pid)")
                perPane[uuid] = nova
            } else {
                perPane[uuid] = sessio
            }
        }

        let iniciCanonic = Rutes.canonica(inici)
        var lligades = Set<Int32>()
        let finestres = finestresWarp.map { finestra in
            FinestraLlegida(
                numero: finestra.numero,
                pestanyaActiva: finestra.pestanyaActiva,
                pestanyes: finestra.pestanyes.map { pestanya in
                    PestanyaLlegida(
                        posicio: pestanya.posicio,
                        titol: pestanya.titol,
                        color: pestanya.color,
                        panes: pestanya.panes.map { pane in
                            let (carpeta, origen) = carpetaDe(pane, iniciCanonic: iniciCanonic)
                            let claude = perPane[pane.uuid]
                            if let claude { lligades.insert(claude.pid) }
                            var esCarpeta: ObjCBool = false
                            let existeix = FileManager.default.fileExists(atPath: carpeta, isDirectory: &esCarpeta)
                                && esCarpeta.boolValue
                            return PaneLlegit(uuid: pane.uuid, carpeta: carpeta, origenCarpeta: origen,
                                              carpetaExisteix: existeix, claude: claude)
                        })
                })
        }
        sessions.removeAll { lligades.contains($0.pid) }
        return LecturaWarp(finestres: finestres, sessionsSensePestanya: sessions, avisos: avisos,
                           sessionsNoInteractives: noInteractives, warpObert: processos.warpObert(),
                           terminals: processos.terminalsDeWarp(), warpDesaFinestres: desaFinestres)
    }

    /// Carpeta del pane. Si Warp hi té la carpeta d'inici, sovint és perquè l'ha perduda en restaurar-se:
    /// llavors es fa servir la de l'última comanda de l'historial, si n'hi ha.
    private func carpetaDe(_ pane: PaneWarp, iniciCanonic: String) -> (String, OrigenCarpeta) {
        let cwd = pane.cwd.map(Rutes.canonica)
        if cwd == nil || cwd == iniciCanonic, let pwd = pane.darrerPwd.map(Rutes.canonica), pwd != iniciCanonic {
            return (pwd, .historial)
        }
        return (cwd ?? iniciCanonic, .pane)
    }
}
