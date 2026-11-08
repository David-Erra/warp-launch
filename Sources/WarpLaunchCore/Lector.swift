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
    /// On és Warp Stable, segons macOS, i si hi ha Warp Preview (D-P12, 0.29.2). Es mira a cada lectura: Warp es pot
    /// instal·lar o moure amb l'app oberta. L'app i el CLI hi posen `TrobaWarp.delSistema` (l'obridor); les proves, una de
    /// fixa. El Warp que compta és `installacio()`, que també mira quin corre.
    public var warp: @Sendable () -> InstallacioWarp
    /// Carpeta d'inici de l'usuari. Un pane amb aquesta carpeta probablement l'ha perduda en restaurar-se.
    public var inici: String

    /// Cap paràmetre no té valor per defecte: una prova que se n'oblidés un llegiria Warp, Claude o els processos de debò, i
    /// cap guarda de línia no ho veuria (el valor per defecte no surt a la crida, i els arguments poden ocupar diverses
    /// línies). L'app i el CLI hi posen les rutes de debò (`LectorWarp.rutaPerDefecte`, `LectorAjustosWarp.rutaPerDefecte` i
    /// `LectorSessions.carpetaPerDefecte`), els processos del sistema, la instal·lació de macOS i la carpeta d'inici.
    public init(rutaWarp: URL,
                rutaAjustos: URL?,
                carpetaSessions: URL,
                processos: any FontProcessos,
                warp: @escaping @Sendable () -> InstallacioWarp,
                inici: String) {
        self.rutaWarp = rutaWarp
        self.rutaAjustos = rutaAjustos
        self.carpetaSessions = carpetaSessions
        self.processos = processos
        self.warp = warp
        self.inici = inici
    }

    /// El Warp que compta (decisió 4, 0.31.1): el Warp Stable que corre, si n'hi ha un, encara que no sigui el que diu
    /// macOS (`InstallacioWarp.ambLaCopiaOberta`), i si no, el de `warp`. És el que la lectura mira si és obert, i on
    /// l'app i el CLI obren les finestres (`ObreWarp`).
    public func installacio() -> InstallacioWarp { warp().ambLaCopiaOberta(processos) }

    /// Si Warp Stable és obert (el d'`installacio()`), sense llegir res més.
    public func warpObert() -> Bool { processos.warpObert(executable: installacio().executable) }

    /// Si el Warp Stable que corre (el d'`installacio()`) ja ha acabat d'arrencar, amb algun terminal
    /// (`FontProcessos.warpHaAcabatDArrencar`): només llavors l'app crea `settings.toml` (ronda 5).
    public func warpHaAcabatDArrencar() -> Bool { processos.warpHaAcabatDArrencar(executable: installacio().executable) }

    /// Per què no hi ha cap Warp Stable (0.31.1): cap Warp, o només Warp Preview. `nil` si n'hi ha un (el d'`installacio()`).
    /// On no s'ha instal·lat mai Warp Stable, tampoc no hi ha la seva base.
    public func senseWarpStable() -> WarpPreview? {
        let warp = installacio()
        return warp.hiHaStable ? nil : warp.preview(processos, stableObert: false)
    }

    /// La lectura de l'app: `llegeix(base:)`, però sense la base de Warp no falla amb «no trobo la base de Warp». Llegeix
    /// els processos, com amb la configuració de debò (`.mai`), i la lectura diu que no se'n saben les finestres
    /// (`warpDesaFinestres` a `false`) i per què: que no hi ha cap Warp Stable (`warpPreview`, `senseWarpStable`) o, amb Warp
    /// Stable, que encara no ha desat res (`warpSenseBase`). Així, amb una carpeta de prova (`.segonsAjust`) i en refrescar la
    /// foto (`.sempre`), l'app diu el mateix que amb la configuració de debò. El CLI no la fa servir: falla, i diu per què
    /// (`OrdreCLI`).
    public func llegeixDeLApp(base: BaseWarp) throws -> LecturaWarp {
        do {
            return try llegeix(base: base)
        } catch ErrorLectura.noHiHaBase {
            let ambStable = senseWarpStable() == nil
            var lectura = try llegeix(base: .mai)
            if ambStable { lectura.warpSenseBase = true }
            return lectura
        }
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
        let warp = installacio()
        let obert = processos.warpObert(executable: warp.executable)
        return LecturaWarp(finestres: finestres, sessionsSensePestanya: sessions, avisos: avisos,
                           sessionsNoInteractives: noInteractives, warpObert: obert,
                           terminals: processos.terminalsDeWarp(executable: warp.executable), warpDesaFinestres: desaFinestres,
                           warpPreview: warp.preview(processos, stableObert: obert))
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
