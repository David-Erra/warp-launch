import Foundation

/// Escriure un fitxer sencer o gens: el fitxer nou es crea al costat, es sincronitza i es posa al seu lloc d'un sol
/// cop (`rename`). Ho fan servir la configuració i `estat.json`.
enum EscripturaAtomica {
    /// Crea un fitxer que no existia (si existeix, `EEXIST`) amb aquests permisos, l'escriu i el sincronitza.
    static func creaFitxerNou(_ dades: Data, a url: URL, permisos: Int) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let fitxer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            guard fchmod(fd, mode_t(permisos & 0o7777)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try fitxer.write(contentsOf: dades)
            try fitxer.synchronize()
            try fitxer.close()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Escriu `dades` a `desti`: primer un fitxer temporal al costat, i després el canvi d'un sol cop. Si falla, el
    /// fitxer que hi havia queda igual.
    static func escriu(_ dades: Data, a desti: URL, permisos: Int = 0o644) throws {
        let carpeta = desti.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let temporal = carpeta.appending(path: ".\(desti.lastPathComponent).\(UUID().uuidString).tmp")
        try creaFitxerNou(dades, a: temporal, permisos: permisos)
        guard rename(temporal.path, desti.path) == 0 else {
            let codi = errno
            try? FileManager.default.removeItem(at: temporal)
            throw POSIXError(POSIXErrorCode(rawValue: codi) ?? .EIO)
        }
    }
}
