import Foundation

public enum Rutes {
    /// Ruta canònica d'una carpeta o fitxer: resol els symlinks i posa les majúscules tal com són al disc.
    /// Warp desa la ruta tal com es va escriure (`~/documents/codi/…`) i Claude, la canònica (`~/Codi/…`):
    /// abans de comparar-les cal passar-les totes dues per aquí.
    /// Si la ruta no existeix, la retorna normalitzada (sense `..` ni `/` repetides), amb les majúscules intactes.
    public static func canonica(_ ruta: String) -> String {
        let normalitzada = (ruta as NSString).standardizingPath
        let fd = open(normalitzada, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return normalitzada }
        defer { close(fd) }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return normalitzada }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// Com `canonica`, també per a una carpeta que encara no existeix: fa canònic l'avantpassat més profund que
    /// existeix (enllaços, majúscules i `/System/Volumes/Data` resolts) i hi afegeix la resta tal com és.
    /// `nil` si no es pot saber on va a parar: hi ha un `..` o un enllaç trencat pel camí.
    public static func canonicaFinsOnExisteix(_ ruta: String) -> String? {
        guard ruta.hasPrefix("/") else { return nil }
        let components = (ruta as NSString).pathComponents.filter { $0 != "/" && $0 != "." }
        if components.contains("..") { return nil }
        var existents = components
        var resta: [String] = []
        while !existents.isEmpty {
            let cami = "/" + existents.joined(separator: "/")
            var info = stat()
            if lstat(cami, &info) == 0 {
                // Existeix; si és un enllaç, ha d'apuntar a alguna cosa.
                guard stat(cami, &info) == 0 else { return nil }
                break
            }
            resta.insert(existents.removeLast(), at: 0)
        }
        let base = canonica("/" + existents.joined(separator: "/"))
        return resta.reduce(base) { ($0 as NSString).appendingPathComponent($1) }
    }

    /// Carpeta de la configuració de Warp Launch (D8): `~/.config/warp-launch`. Només l'app i el CLI la fan servir;
    /// les proves, mai.
    public static func carpetaConfiguracio(inici: String) -> URL {
        URL(filePath: inici).appending(path: ".config/warp-launch", directoryHint: .isDirectory)
    }

    /// El contrari d'`abreujada`: `~` i `~/…` passen a la carpeta d'inici; la resta, tal com està escrita.
    public static func desabreujada(_ ruta: String, inici: String) -> String {
        if ruta == "~" { return inici }
        guard ruta.hasPrefix("~/") else { return ruta }
        return (inici.hasSuffix("/") ? String(inici.dropLast()) : inici) + ruta.dropFirst()
    }

    /// Escriu la carpeta d'inici com a `~` (només per mostrar-la).
    public static func abreujada(_ ruta: String, inici: String) -> String {
        if ruta == inici { return "~" }
        let prefix = inici.hasSuffix("/") ? inici : inici + "/"
        return ruta.hasPrefix(prefix) ? "~/" + ruta.dropFirst(prefix.count) : ruta
    }
}
