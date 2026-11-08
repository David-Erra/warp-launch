import Foundation

/// Les carpetes on Claude ja no pregunta si hi confies (`projects.<carpeta>.hasTrustDialogAccepted` de
/// `~/.claude.json`). Si hi pregunta, la pestanya s'atura a esperar una tecla: el full d'obertura ho avisa (fase 3.1).
public struct Confianca: Sendable, Equatable {
    /// Carpetes amb la confiança acceptada, tal com les escriu Claude (sense resoldre enllaços: vegeu `confiada`).
    public var confiades: Set<String>
    /// Carpeta d'inici canònica: Claude no hi desa mai la confiança, i sempre pregunta.
    public var inici: String

    public init(confiades: Set<String>, inici: String) {
        self.confiades = confiades
        self.inici = inici
    }

    /// Si Claude obrirà la carpeta sense preguntar: la carpeta real o una de les seves carpetes pare té la confiança. Claude
    /// compara les rutes tal com són: la confiança de `~/Documents/codi/x` (un enllaç) no compta per a `~/codi/x`, que
    /// és on corre (docs/fets-verificats.md, 05/11/2026).
    public func confiada(_ carpeta: String) -> Bool {
        let carpeta = Rutes.canonica(carpeta)
        guard carpeta != inici else { return false }
        var actual = carpeta
        while true {
            if confiades.contains(actual) { return true }
            let pare = (actual as NSString).deletingLastPathComponent
            guard pare != actual, !pare.isEmpty else { return false }
            actual = pare
        }
    }
}

/// Llegeix `~/.claude.json`. **Només lectura**, i només aquest camp: la resta del fitxer no surt d'aquí.
public struct LectorConfianca: Sendable {
    public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")

    /// Les claus que es llegeixen: les fa servir també el diagnòstic, per dir si Claude Code les ha canviades.
    static let clauProjectes = "projects"
    static let clauConfianca = "hasTrustDialogAccepted"

    public var ruta: URL

    /// Sense valor per defecte, com `LectorSessions`: una prova que se l'oblidés llegiria el `~/.claude.json` de debò, i cap
    /// guarda de línia no ho veuria (el valor per defecte no surt a la crida). L'app i el CLI hi posen
    /// `LectorConfianca.rutaPerDefecte`.
    public init(ruta: URL) {
        self.ruta = ruta
    }

    /// `nil` si el fitxer no es pot llegir o no és el que s'espera: llavors el full no avisa de res.
    public func llegeix(inici: String) -> Confianca? {
        guard let dades = try? Data(contentsOf: ruta),
              let json = (try? JSONSerialization.jsonObject(with: dades)) as? [String: Any],
              let projectes = json[Self.clauProjectes] as? [String: Any] else { return nil }
        let confiades = projectes.compactMap { carpeta, valor -> String? in
            guard let valor = valor as? [String: Any], valor[Self.clauConfianca] as? Bool == true else { return nil }
            return Self.senseBarresDeMes(carpeta)
        }
        return Confianca(confiades: Set(confiades), inici: Rutes.canonica(inici))
    }

    /// `/a//b/` → `/a/b`. No resol enllaços.
    private static func senseBarresDeMes(_ ruta: String) -> String {
        "/" + ruta.split(separator: "/").joined(separator: "/")
    }
}
