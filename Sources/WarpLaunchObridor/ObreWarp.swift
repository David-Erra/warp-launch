import AppKit
import WarpLaunchCore

/// L'única peça que fa obrir alguna cosa a Warp (fase 3.1, D5): li dona l'URL de llançament d'un fitxer temporal
/// (`URLLlancament`), i l'obre si és tancat, i res més. La fan servir l'app i, a la 0.23.0, el CLI amb `--obre` (D17).
/// **Només s'hi arriba després de la confirmació** (el full, o `--obre` amb l'OK d'en David).
public enum ObreWarp {
    public enum ErrorObrir: Error, Equatable, CustomStringConvertible {
        /// A `/Applications/Warp.app` no hi ha Warp (o no és el de debò): no s'obre res.
        case senseWarp
        case obrir(String)

        public var description: String {
            switch self {
            case .senseWarp: "a Aplicacions no hi ha Warp (\(AppWarp.identificador))"
            case let .obrir(error): error
            }
        }
    }

    /// Demana a Warp que obri el fitxer. Sempre amb l'app d'Aplicacions, i no amb la que el sistema tingui per a les
    /// URL de Warp. No espera la finestra: això ho fa `ConfirmacioObertura`.
    @MainActor
    public static func obre(_ url: URLLlancament, app: AppWarp = .real) async throws(ErrorObrir) {
        guard app.esWarp else { throw .senseWarp }
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
    /// d'Aplicacions. No diu res de si ha acabat d'arrencar: això ho mira `Obertura`, que tampoc no espera que aquesta crida torni.
    @MainActor
    public static func engega(app: AppWarp = .real) async throws(ErrorObrir) {
        guard app.esWarp else { throw .senseWarp }
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
