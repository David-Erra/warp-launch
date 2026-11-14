import AppKit
import WarpLaunchCore

/// L'única peça que actua sobre Warp (fase 3.1, D5): li dona l'URL de llançament d'un fitxer temporal (`URLLlancament`),
/// l'obre si és tancat i, des de la 1.0.3, tanca la finestra que Warp obre sola en arrencar, quan l'ha engegat l'URL
/// (`acabaShellDeLaFinestraDeWarp`). Res més. La fan servir l'app i, a la 0.23.0, el CLI amb `--obre` (D17).
/// **Només s'hi arriba després de la confirmació** (el full, o `--obre` amb l'OK d'en David).
public enum ObreWarp {
    public enum ErrorObrir: Error, Equatable, CustomStringConvertible {
        /// No s'ha trobat Warp Stable (ni cap que corri, ni el que diu macOS, ni el d'Aplicacions), o no és el de debò: no
        /// s'obre res. Des de la 0.31.1, la lectura ja ho diu abans (`WarpPreview.capWarp`).
        case senseWarp
        /// Només hi ha Warp Preview, que encara no és compatible (D-P12, 0.29.2): no s'obre res.
        case nomesPreview
        case obrir(String)

        public var description: String {
            switch self {
            case .senseWarp: "no s'ha trobat Warp Stable (\(AppWarp.identificador)) en aquest Mac"
            case .nomesPreview: WarpPreview.nomesPreview.text
            case let .obrir(error): error
            }
        }
    }

    /// L'app de Warp Stable que es pot obrir, o per què no n'hi ha cap.
    private static func app(_ warp: InstallacioWarp) throws(ErrorObrir) -> AppWarp {
        guard warp.app.esWarp else { throw warp.executablePreview == nil ? .senseWarp : .nomesPreview }
        return warp.app
    }

    /// Demana a Warp que obri el fitxer. Sempre amb l'app de Warp Stable que la lectura mira si és oberta
    /// (`Lector.installacio()`: la que corre, si n'hi ha una, decisió 4, 0.31.1), i no amb la que el sistema tingui per a
    /// les URL de Warp. No espera la finestra: això ho fa `ConfirmacioObertura`.
    @MainActor
    public static func obre(_ url: URLLlancament, warp: InstallacioWarp) async throws(ErrorObrir) {
        let app = try app(warp)
        let configuracio = NSWorkspace.OpenConfiguration()
        configuracio.activates = true
        configuracio.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.open([url.url], withApplicationAt: app.url, configuration: configuracio)
        } catch {
            throw .obrir(error.localizedDescription)
        }
    }

    /// Obre Warp, sense cap fitxer: si restaura la sessió, cal veure què ha restaurat abans de demanar-li res. Sempre l'app
    /// de Warp Stable de la lectura (`Lector.installacio()`). No diu res de si ha acabat d'arrencar: això ho mira
    /// `Obertura`, que tampoc no espera que aquesta crida torni.
    @MainActor
    public static func engega(warp: InstallacioWarp) async throws(ErrorObrir) {
        let app = try app(warp)
        let configuracio = NSWorkspace.OpenConfiguration()
        configuracio.activates = true
        configuracio.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuracio)
        } catch {
            throw .obrir(error.localizedDescription)
        }
    }

    /// Tanca la finestra que Warp obre sola en arrencar (1.0.3, decisió d'en David del 14/11/2026; regla 2, excepció): acaba
    /// el shell de la seva única pestanya amb SIGHUP, el que rep un shell quan es tanca el terminal (zsh interactiu no fa cas
    /// del de terminar), i Warp tanca la pestanya i la finestra, com amb `exit`. L'única crida de senyal de tot `Sources/`.
    /// - Només el candidat de `FinestraDeWarp.tria`, amb totes les seves condicions, i només quan l'URL de la primera finestra
    ///   ha engegat Warp en aquesta mateixa acció (`Obertura`, `OrdreCLI`).
    /// - Just abans, ho torna a comprovar (`Candidat.encaraEs`): el mateix pid amb la mateixa hora d'inici i el mateix pare
    ///   (el pid no s'ha reutilitzat), a la carpeta d'inici, i encara sense cap fill.
    /// - Un sol intent, i res més fort: si el shell no acaba, la finestra hi queda.
    public static func acabaShellDeLaFinestraDeWarp(_ candidat: FinestraDeWarp.Candidat,
                                                    processos: any FontProcessos) -> FinestraDeWarp.Resultat {
        guard candidat.encaraEs(processos) else {
            return .dubte("el terminal \(candidat.pid) ha canviat abans d'acabar-lo")
        }
        guard kill(candidat.pid, SIGHUP) == 0 else {
            return .dubte("el senyal al terminal \(candidat.pid) ha fallat (errno \(errno))")
        }
        return .tancada(candidat.pid)
    }
}
