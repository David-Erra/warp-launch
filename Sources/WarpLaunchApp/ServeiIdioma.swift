import Foundation
import WarpLaunchUI

/// La llengua de l'app (docs/disseny.md, secció 12, F4): la preferència `AppleLanguages` del domini de l'app, que macOS llegeix
/// en obrir-la. És l'únic fitxer de `Sources` que fa servir les preferències del sistema, i només per a aquesta clau
/// (excepció de l'autor; `nomesElServeiDIdiomaFaServirLesPreferencies`): llegeix la de l'app i la del Mac (el domini global,
/// per dir quina és la del sistema) i desa o esborra la de l'app. Sense identificador de paquet (l'executable sol, sense
/// `.app`), no hi ha selector.
@MainActor
enum ServeiIdioma {
    private static let clau = "AppleLanguages"

    static var entorn: SelectorIdioma.Entorn? {
        guard let domini = Bundle.main.bundleIdentifier else { return nil }
        return SelectorIdioma.Entorn(
            delSistema: { UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[clau] as? [String] ?? [] },
            deLApp: { UserDefaults.standard.persistentDomain(forName: domini)?[clau] as? [String] },
            desa: { llengues in
                if let llengues {
                    UserDefaults.standard.set(llengues, forKey: clau)
                } else {
                    UserDefaults.standard.removeObject(forKey: clau)
                }
            })
    }
}
