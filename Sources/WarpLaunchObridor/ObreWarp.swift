import AppKit
import WarpLaunchCore

/// L'única peça que fa obrir alguna cosa a Warp (fase 3.1, D5): li dona l'URL de llançament d'un fitxer temporal
/// (`URLLlancament`), i l'obre si és tancat, i res més. La fan servir l'app i, a la 0.23.0, el CLI amb `--obre` (D17).
/// **Només s'hi arriba després de la confirmació** (el full, o `--obre` amb l'OK d'en David).
public enum ObreWarp {
    public enum ErrorObrir: Error, Equatable, CustomStringConvertible {
        /// No s'ha trobat Warp Stable (ni el que diu macOS ni el d'Aplicacions), o no és el de debò: no s'obre res.
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
}
