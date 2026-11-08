import Foundation

/// Llegeix de `~/.warp/settings.toml` si Warp restaura la sessió (`general.restore_session`). **Només lectura.**
///
/// Amb la restauració desactivada, Warp no desa les finestres a `warp.sqlite` (la seva acció `save_app` surt de seguida,
/// docs/fets-verificats.md, 05/11/2026): el que hi ha a la base és de l'última vegada que era activa, i no diu què hi ha
/// obert.
public struct LectorAjustosWarp: Sendable {
    public static let rutaPerDefecte = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".warp/settings.toml")

    public var ruta: URL

    /// Sense valor per defecte, com `LectorSessions`: una prova que se l'oblidés llegiria el `settings.toml` de debò, i cap
    /// guarda de línia no ho veuria (el valor per defecte no surt a la crida). L'app i el CLI hi posen `rutaPerDefecte`, al
    /// seu `Lector`.
    public init(ruta: URL) {
        self.ruta = ruta
    }

    /// Si Warp desa les finestres. Per defecte, sí: només `restore_session = false` diu el contrari. Sense la línia (qui no
    /// l'ha canviat mai: Warp només escriu els ajustos canviats), sense fitxer, o si no es pot llegir, també (és el valor
    /// per defecte de Warp). Ho miren el CLI, el diagnòstic i l'app amb una carpeta de prova (`BaseWarp.segonsAjust`); amb
    /// la de debò, l'app gestiona l'ajust (`AjustRestauracio`, que hi afegeix la línia si no hi és).
    public func desaFinestres() -> Bool {
        guard let dades = try? Data(contentsOf: ruta) else { return true }
        return Self.desaFinestres(toml: String(decoding: dades, as: UTF8.self))
    }

    /// No és un lector de TOML: només busca aquesta clau, a la taula `[general]` o amb el nom sencer a l'arrel.
    static func desaFinestres(toml: String) -> Bool {
        var taula = ""
        for linia in toml.split(whereSeparator: \.isNewline) {
            let text = linia.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[") {
                taula = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            let parts = text.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let clau = taula.isEmpty ? parts[0] : "\(taula).\(parts[0])"
            if clau == "general.restore_session" { return parts[1] != "false" }
        }
        return true
    }
}
