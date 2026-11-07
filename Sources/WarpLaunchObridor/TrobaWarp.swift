import AppKit
import WarpLaunchCore

/// On és Warp en aquest Mac, segons macOS (D-P12, 0.29.2): Warp Stable en qualsevol carpeta, i Warp Preview, per dir que
/// encara no és compatible. És l'única pregunta a Launch Services de tot el codi, i només llegeix: no obre res. La fan
/// servir l'app i el CLI; cap prova no hi arriba (no depenen de l'obridor), i la guarda la deixa només aquí.
public enum TrobaWarp: Sendable {
    public static func delSistema() -> InstallacioWarp {
        InstallacioWarp.troba(aplicacions: AppWarp.rutaPerDefecte,
                              cerca: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) })
    }
}
