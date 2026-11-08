import Foundation

/// Mira i canvia la línia `restore_session` de `[general]` al `settings.toml` de Warp (D19). És l'única cosa de Warp que
/// l'app pot escriure (regla 7 de CLAUDE.md), i fa les mateixes comprovacions que `scripts/warp-restauracio.sh`: si el
/// fitxer no té exactament la forma esperada, no toca res. No hi ha ruta per defecte: la de debò només la dona l'app.
public struct AjustRestauracio: Sendable {
    public struct Refusat: Error, Equatable, CustomStringConvertible {
        public var description: String
    }

    public var ruta: URL
    /// On es prepara el fitxer nou: fora de la carpeta de Warp, perquè no hi quedi res, i al mateix volum.
    public var carpetaTemporal: URL

    public init(ruta: URL, carpetaTemporal: URL = FileManager.default.temporaryDirectory) {
        self.ruta = ruta
        self.carpetaTemporal = carpetaTemporal
    }

    /// El valor actual.
    public func valor() throws(Refusat) -> Bool {
        try Self.analitza(try llegeix().text).valor
    }

    /// Posa el valor. Torna si ha canviat res. Si Warp ha escrit el fitxer mentrestant, no toca res i ho diu.
    @discardableResult
    public func posa(_ nou: Bool) throws(Refusat) -> Bool {
        let (dades, text) = try llegeix()
        let trobada = try Self.analitza(text)
        guard trobada.valor != nou else { return false }
        let resultat = Data(Self.canvia(text, linia: trobada.linia, a: nou).utf8)

        var fitxer = stat(), carpeta = stat()
        guard stat(ruta.path, &fitxer) == 0, stat(carpetaTemporal.path, &carpeta) == 0 else {
            throw Refusat(description: "no es pot mirar on és «\(ruta.path)»")
        }
        // `rename` no ho miraria: un fitxer protegit no es toca.
        guard access(ruta.path, W_OK) == 0 else { throw Refusat(description: "«\(ruta.path)» és de només lectura") }
        guard fitxer.st_dev == carpeta.st_dev else {
            throw Refusat(description: "la carpeta temporal no és al mateix volum que «\(ruta.path)»")
        }
        let temporal = carpetaTemporal.appending(path: ".warp-settings-\(UUID().uuidString).tmp")
        do {
            try EscripturaAtomica.creaFitxerNou(resultat, a: temporal, permisos: Int(fitxer.st_mode & 0o7777))
        } catch {
            throw Refusat(description: "no s'ha pogut preparar el fitxer: \(error)")
        }
        // Els atributs estesos de l'original, com `cp -p` a l'script. Si no es pot, no és motiu per aturar res.
        copyfile(ruta.path, temporal.path, nil, copyfile_flags_t(COPYFILE_XATTR))
        // Warp l'escriu en calent: el que s'acaba de llegir encara ha de ser el que hi ha.
        guard (try? Data(contentsOf: ruta)) == dades else {
            try? FileManager.default.removeItem(at: temporal)
            throw Refusat(description: "«\(ruta.path)» acaba de canviar")
        }
        guard rename(temporal.path, ruta.path) == 0 else {
            let codi = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporal)
            throw Refusat(description: "no s'ha pogut escriure «\(ruta.path)»: \(codi)")
        }
        return true
    }

    private func llegeix() throws(Refusat) -> (dades: Data, text: String) {
        var info = stat()
        guard lstat(ruta.path, &info) == 0 else { throw Refusat(description: "no hi ha «\(ruta.path)»") }
        // `rename` substituiria l'enllaç, no el fitxer.
        guard info.st_mode & S_IFMT == S_IFREG else { throw Refusat(description: "«\(ruta.path)» no és un fitxer normal") }
        guard let dades = try? Data(contentsOf: ruta), let text = String(data: dades, encoding: .utf8) else {
            throw Refusat(description: "no es pot llegir «\(ruta.path)»")
        }
        return (dades, text)
    }

    /// Només una aparició a tot el fitxer, i que sigui una línia de la taula `[general]`, amb un valor `true` o `false`.
    static func analitza(_ text: String) throws(Refusat) -> (linia: Int, valor: Bool) {
        // «\r\n» és un sol caràcter de Swift, i separar línies per «\n» no el veuria: una taula podria quedar amagada.
        guard !text.unicodeScalars.contains("\r") else { throw Refusat(description: "«settings.toml» té salts de línia CRLF") }
        guard text.hasSuffix("\n") else { throw Refusat(description: "«settings.toml» no acaba amb un salt de línia") }
        let linies = text.split(separator: "\n", omittingEmptySubsequences: false)
        let aparicions = linies.filter { $0.contains("restore_session") }.count
        guard aparicions == 1 else {
            throw Refusat(description: "«restore_session» hi surt \(aparicions) vegades, i n'hi hauria d'haver 1")
        }
        var taula = ""
        for (numero, linia) in linies.enumerated() {
            let sensePunta = linia.drop { $0 == " " || $0 == "\t" }
            if sensePunta.hasPrefix("[") {
                taula = linia.filter { $0 != " " && $0 != "\t" }
                continue
            }
            guard linia.contains("restore_session") else { continue }
            guard taula == "[general]", let igual = sensePunta.firstIndex(of: "="),
                  sensePunta[..<igual].trimmingCharacters(in: .whitespaces) == "restore_session"
            else { throw Refusat(description: "«restore_session» no és una línia de la taula [general]") }
            switch sensePunta[sensePunta.index(after: igual)...].prefix(while: { $0 != "#" }).trimmingCharacters(in: .whitespaces) {
            case "true": return (numero, true)
            case "false": return (numero, false)
            default: throw Refusat(description: "el valor de «restore_session» no és true ni false")
            }
        }
        throw Refusat(description: "«restore_session» no és una línia de la taula [general]")
    }

    /// El mateix text, amb només el valor de la línia canviat: un comentari al final queda igual.
    private static func canvia(_ text: String, linia numero: Int, a nou: Bool) -> String {
        var linies = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let linia = linies[numero]
        // `analitza` ja ha comprovat que el valor és just després del `=`.
        let igual = linia.firstIndex(of: "=")!
        let cua = linia[linia.index(after: igual)...]
        let vell = nou ? "false" : "true"
        linies[numero] = String(linia[...igual]) + cua.replacing(vell, with: nou ? "true" : "false", maxReplacements: 1)
        return linies.joined(separator: "\n")
    }
}

extension LecturaWarp {
    /// Què hi ha a la base de Warp: finestres, pestanyes, títols, colors i panes. Serveix per veure si Warp hi ha desat,
    /// sense que hi compti res de les sessions.
    public var fotoFinestres: [String] {
        finestres.flatMap { f in
            f.pestanyes.flatMap { p in
                p.panes.map { "\(f.numero)/\(p.posicio)/\(p.titol ?? "")/\(p.color ?? "")/\($0.uuid)/\($0.carpeta)" }
            }
        }
    }

    /// Si la base diu el mateix que els terminals vius: tants panes com terminals, i tots els que se saben hi són. Un
    /// shell sense cap fill no diu el seu pane.
    public var finestresQuadrenAmbTerminals: Bool {
        func net(_ pane: String) -> String { pane.lowercased().replacingOccurrences(of: "-", with: "") }
        let aLaBase = Set(finestres.flatMap(\.pestanyes).flatMap(\.panes).map { net($0.uuid) })
        return aLaBase.count == terminals.count && terminals.allSatisfy { $0.pane.map { aLaBase.contains(net($0)) } ?? true }
    }

    /// L'avís quan Warp és tancat: no se sap de quan és, i no hi ha cap sessió viva d'on treure les opcions de Claude.
    /// No diu què en surt: en tornar a importar sobre alguna pestanya, la plantilla (D11); en una configuració nova o
    /// sense cap pestanya, només terminal (D-P5a). Les xifres del full ho diuen.
    public static let avisFotoWarpTancat = "Warp és tancat: és la foto de l'última vegada que va desar, potser antiga. "
        + "Sense sessions vives, no se sap on hi havia Claude obert: en importar, cap pestanya conserva la seva ordre."

    /// L'avís quan la base no diu el mateix que els terminals vius (D19).
    public var avisFinestresAntigues: String {
        let pestanyes = finestres.flatMap(\.pestanyes).flatMap(\.panes).count
        return "Warp no ha desat les finestres: n'hi ha \(Plural.compta(pestanyes, "pestanya", "pestanyes")) desades i "
            + "\(Plural.compta(terminals.count, "terminal viu", "terminals vius")). Pot ser antic: canvia de finestra a Warp i torna a llegir."
    }
}
