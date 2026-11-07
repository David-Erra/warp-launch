import Foundation

/// Llegeix i desa `estat.json` a la carpeta de la configuració. **No té ruta per defecte**, com
/// `MagatzemConfiguracio`: l'app hi passa la seva carpeta, i les proves, una de temporal. No en fa còpies: és de l'app.
public struct MagatzemEstat: Sendable {
    public let carpeta: URL

    public init(carpeta: URL) {
        self.carpeta = carpeta
    }

    public var fitxer: URL { carpeta.appending(path: EstatApp.nomFitxer) }

    /// L'estat del disc, o un de buit si encara no n'hi ha. No escriu ni crea res.
    public func carrega() throws(EstatApp.ErrorEstat) -> EstatApp {
        try EstatApp.llegeix(fitxer: fitxer)
    }

    /// Desa l'estat. Si el del disc és d'una versió més nova o no es pot llegir, no el trepitja: l'error ho diu.
    public func desa(_ estat: EstatApp) throws(EstatApp.ErrorEstat) {
        _ = try carrega()
        let dades: Data
        do {
            dades = try estat.json()
        } catch {
            throw .escriptura("no s'ha pogut generar el JSON: \(error)")
        }
        guard (try? EstatApp.llegeix(dades)) == estat else { throw .escriptura("el JSON no es torna a llegir igual") }
        do {
            try EscripturaAtomica.escriu(dades, a: fitxer)
        } catch {
            throw .escriptura(error.localizedDescription)
        }
    }
}
