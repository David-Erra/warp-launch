import Foundation

/// Llegeix i desa la configuració a una carpeta (`~/.config/warp-launch/` per a en David; a les proves, una de
/// temporal). **No té ruta per defecte:** qui el crea la hi ha de passar.
///
/// - Llegir no escriu ni crea res.
/// - Desar comprova que el fitxer no hagi canviat fora de l'app i que el JSON nou es torni a llegir igual. Després
///   escriu el fitxer nou al costat, fa la còpia si cal i el posa al seu lloc d'un sol cop (`rename`). Les còpies
///   que sobren només s'esborren quan el fitxer nou ja és al seu lloc.
public struct MagatzemConfiguracio: Sendable {
    public static let nomFitxer = "configuracio.json"
    public static let nomCopies = "copies"
    /// Còpies pròpies que es guarden. Només compten els fitxers amb el nom exacte que posa l'app
    /// (`configuracio-AAAAMMDD-HHMMSS-<motiu>[-N].json`); la resta de `copies/` no es toca mai.
    public static let maxCopies = 20

    public let carpeta: URL
    /// Carpeta d'inici, per expandir `~/…`.
    public let inici: String
    let ara: @Sendable () -> Date
    let zona: TimeZone
    /// `rename(2)`. Només les proves el canvien, per fer-lo fallar després de la còpia.
    var reanomena: @Sendable (String, String) -> Int32 = { rename($0, $1) }

    public init(carpeta: URL, inici: String, ara: @escaping @Sendable () -> Date = { Date() }, zona: TimeZone = .current) {
        self.carpeta = carpeta
        self.inici = inici
        self.ara = ara
        self.zona = zona
    }

    public var fitxer: URL { carpeta.appending(path: Self.nomFitxer) }
    public var copies: URL { carpeta.appending(path: Self.nomCopies) }

    /// Llegeix la configuració. `nil` si encara no n'hi ha. No escriu ni crea res.
    public func carrega() throws(ErrorMagatzem) -> ConfiguracioCarregada? {
        guard let dades = try llegeixSiExisteix() else { return nil }
        do {
            let llegida = try Configuracio.llegeix(dades, inici: inici)
            return ConfiguracioCarregada(configuracio: llegida.configuracio, avisos: llegida.avisos, empremta: dades)
        } catch {
            throw .format(error)
        }
    }

    /// Els bytes del fitxer tal com són ara, o `nil` si no n'hi ha: per saber si ha canviat fora de l'app sense
    /// interpretar-lo. No escriu res.
    public func bytesActuals() throws(ErrorMagatzem) -> Data? {
        try llegeixSiExisteix()
    }

    /// Desa la configuració i en retorna els bytes, que són l'empremta per al desat següent.
    /// - Parameters:
    ///   - empremta: els bytes de l'última lectura o desat; `nil` si el fitxer no existia. Si el disc no hi
    ///     coincideix, el fitxer ha canviat fora de l'app i **no s'escriu res** (`modificadaFora`).
    ///   - motiu: si n'hi ha i el fitxer ja existeix, abans es fa una còpia a `copies/`. Si el fitxer del disc no té
    ///     la forma que escriu l'app (editat a mà), se'n fa còpia igualment (`fora`). Si la còpia falla, no s'escriu.
    @discardableResult
    public func desa(_ configuracio: Configuracio, sobre empremta: Data?,
                     copia motiu: MotiuCopia? = nil) throws(ErrorMagatzem) -> Data {
        let actual = try llegeixSiExisteix()
        guard actual == empremta else { throw .modificadaFora }

        var perDesar = configuracio.normalitzada(inici: inici)
        perDesar.generador = "\(WarpLaunch.nom) \(WarpLaunch.versio)"
        let dades: Data
        do {
            dades = try perDesar.json()
        } catch {
            throw .escriptura(t("no s'ha pogut generar el JSON: \(String(describing: error))"))
        }
        // El que s'escriu s'ha de poder tornar a llegir igual.
        guard let rellegida = try? Configuracio.llegeix(dades, inici: inici).configuracio, rellegida == perDesar else {
            throw .verificacioFallida
        }
        if dades == actual { return dades }  // res no ha canviat: ni còpia ni escriptura

        let fm = FileManager.default
        let desti = destiReal()
        var permisos = 0o644
        if actual != nil {
            guard fm.isWritableFile(atPath: desti.path) else {
                throw .escriptura(t("el fitxer és només de lectura (\(desti.path))"))
            }
            permisos = (try? fm.attributesOfItem(atPath: desti.path))?[.posixPermissions] as? Int ?? permisos
        }

        // 1. El fitxer nou, sencer i al disc, al costat del destí.
        let temporal = desti.deletingLastPathComponent()
            .appending(path: ".\(desti.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try fm.createDirectory(at: desti.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EscripturaAtomica.creaFitxerNou(dades, a: temporal, permisos: permisos)
        } catch {
            throw .escriptura(error.localizedDescription)
        }

        // 2. La còpia del que hi ha ara. Si falla, no es toca res.
        var copiaNova: URL?
        if let actual, let motiu = motiu ?? (Self.esCanonic(actual, inici: inici) ? nil : .fora) {
            do throws(ErrorMagatzem) {
                copiaNova = try fesCopia(actual, motiu: motiu, permisos: permisos)
            } catch {
                try? fm.removeItem(at: temporal)
                throw error
            }
        }

        // 3. El canvi, d'un sol cop.
        guard reanomena(temporal.path, desti.path) == 0 else {
            let codi = errno
            try? fm.removeItem(at: temporal)
            throw .escriptura(POSIXError(POSIXErrorCode(rawValue: codi) ?? .EIO).localizedDescription)
        }

        // 4. Només ara, amb el fitxer nou al seu lloc, s'esborren les còpies que sobren.
        if let copiaNova { esborraCopiesAntigues(mantenint: copiaNova) }
        return dades
    }

    // MARK: - Fitxers

    /// Si `configuracio.json` és un enllaç simbòlic, s'escriu a la destinació i l'enllaç es manté.
    /// Només es crida després d'haver-lo llegit, de manera que la destinació existeix.
    private func destiReal() -> URL {
        let valors = try? fitxer.resourceValues(forKeys: [.isSymbolicLinkKey])
        return valors?.isSymbolicLink == true ? fitxer.resolvingSymlinksInPath() : fitxer
    }

    /// `nil` només si el fitxer no existeix. Un fitxer que no es pot llegir, o un enllaç trencat, és un error: si
    /// no, l'app creuria que no hi ha configuració i en crearia una de nova al damunt.
    private func llegeixSiExisteix() throws(ErrorMagatzem) -> Data? {
        do {
            return try Data(contentsOf: fitxer)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            if let desti = try? FileManager.default.destinationOfSymbolicLink(atPath: fitxer.path) {
                throw .lectura(t("«\(Self.nomFitxer)» és un enllaç a «\(desti)», que no existeix"))
            }
            return nil
        } catch {
            throw .lectura(error.localizedDescription)
        }
    }

    /// Si els bytes són exactament els que escriuria l'app. Si no ho són (editat a mà, claus desconegudes, id
    /// que falten), en desar es perdria alguna cosa, i per això se'n fa còpia.
    ///
    /// No mira els avisos: els que perden dades (clau desconeguda, id nou, sense plantilla, sense bloc `claude`) ja
    /// fan que els bytes reescrits siguin uns altres. Els que no (una carpeta que no és absoluta, que es desa tal com
    /// és) farien una còpia `fora` a cada desat, i en 20 desats s'esborrarien les còpies bones.
    static func esCanonic(_ dades: Data, inici: String) -> Bool {
        guard let llegida = try? Configuracio.llegeix(dades, inici: inici),
              let tornada = try? llegida.configuracio.json() else { return false }
        return tornada == dades
    }

    /// Fa la còpia i en retorna la ruta. `nil` si la còpia més recent ja té aquests bytes (per exemple, d'un desat
    /// anterior que va fallar en escriure): així els reintents no omplen `copies/` de duplicats.
    private func fesCopia(_ dades: Data, motiu: MotiuCopia, permisos: Int) throws(ErrorMagatzem) -> URL? {
        if let darrera = copiesPropies().first, (try? Data(contentsOf: darrera)) == dades { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = zona
        format.dateFormat = "yyyyMMdd-HHmmss"
        let base = "configuracio-\(format.string(from: ara()))-\(motiu.rawValue)"
        do {
            try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
            var n = 1
            while true {
                let desti = copies.appending(path: n == 1 ? "\(base).json" : "\(base)-\(n).json")
                do {
                    try EscripturaAtomica.creaFitxerNou(dades, a: desti, permisos: permisos)
                    return desti
                } catch let error as POSIXError where error.code == .EEXIST {
                    n += 1
                }
            }
        } catch {
            throw .copiaFallida(error.localizedDescription)
        }
    }

    /// Les còpies que ha fet l'app (fitxers normals amb el nom exacte), de la més nova a la més antiga segons el
    /// nom, no segons la data de modificació.
    func copiesPropies() -> [URL] {
        let fm = FileManager.default
        guard let noms = try? fm.contentsOfDirectory(atPath: copies.path) else { return [] }
        return noms.compactMap { nom -> (url: URL, clau: ClauCopia)? in
            guard let clau = ClauCopia(nom: nom) else { return nil }
            let url = copies.appending(path: nom)
            // attributesOfItem no segueix els enllaços: un enllaç o una carpeta no són còpies.
            guard (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular else { return nil }
            return (url, clau)
        }
        .sorted { $0.clau > $1.clau }
        .map(\.url)
    }

    /// Deixa les `maxCopies` còpies pròpies més recents, i sempre la que s'acaba de fer (encara que el rellotge
    /// hagi anat enrere).
    private func esborraCopiesAntigues(mantenint nova: URL) {
        let altres = copiesPropies().filter { $0.lastPathComponent != nova.lastPathComponent }
        for antiga in altres.dropFirst(Self.maxCopies - 1) { try? FileManager.default.removeItem(at: antiga) }
    }
}

/// Nom d'una còpia pròpia, per ordenar-les: `configuracio-AAAAMMDD-HHMMSS-<motiu>[-N].json`.
struct ClauCopia: Comparable {
    let segell: String
    let n: Int
    let nom: String

    init?(nom: String) {
        let prefix = "configuracio-", sufix = ".json"
        guard nom.hasPrefix(prefix), nom.hasSuffix(sufix) else { return nil }
        let parts = nom.dropFirst(prefix.count).dropLast(sufix.count).split(separator: "-", omittingEmptySubsequences: false)
        func digits(_ s: Substring, _ quants: Int?) -> Bool {
            !s.isEmpty && (quants == nil || s.utf8.count == quants) && s.utf8.allSatisfy { (0x30...0x39).contains($0) }
        }
        guard parts.count == 3 || parts.count == 4, digits(parts[0], 8), digits(parts[1], 6),
              MotiuCopia(rawValue: String(parts[2])) != nil else { return nil }
        if parts.count == 4 {
            guard digits(parts[3], nil), let n = Int(parts[3]), n >= 2 else { return nil }
            self.n = n
        } else {
            self.n = 1
        }
        segell = "\(parts[0])\(parts[1])"
        self.nom = nom
    }

    static func < (a: ClauCopia, b: ClauCopia) -> Bool { (a.segell, a.n, a.nom) < (b.segell, b.n, b.nom) }
}

public struct ConfiguracioCarregada: Sendable, Equatable {
    public var configuracio: Configuracio
    public var avisos: [AvisFormat]
    /// Bytes del fitxer tal com s'han llegit. El desat següent comprova que el disc no hagi canviat.
    public var empremta: Data
}

/// Per què es fa una còpia abans de desar. Surt al nom del fitxer de la còpia.
public enum MotiuCopia: String, Sendable, CaseIterable {
    /// Primer desat de cada sessió de l'app.
    case sessio
    /// Abans d'esborrar una finestra amb pestanyes.
    case esborrat
    /// Abans de tornar a importar de Warp.
    case importacio
    /// El fitxer del disc no té la forma que escriu l'app (editat a mà, amb claus desconegudes o sense id): se'n fa
    /// còpia abans de sobreescriure'l, encara que no s'hagi demanat.
    case fora
}

public enum ErrorMagatzem: Error, Equatable, Sendable, CustomStringConvertible {
    /// El fitxer és malmès o d'una versió més nova: l'editor l'obre en només lectura.
    case format(ErrorConfiguracio)
    /// El fitxer ha canviat (o s'ha creat o esborrat) fora de l'app des de l'última lectura. No s'ha escrit res.
    case modificadaFora
    case copiaFallida(String)
    case lectura(String)
    case escriptura(String)
    /// El JSON generat no es tornava a llegir igual. No s'ha escrit res.
    case verificacioFallida

    public var description: String {
        switch self {
        case let .format(error): error.description
        case .modificadaFora: t("la configuració ha canviat fora de l'app; no s'ha desat res")
        case let .copiaFallida(detall): t("no s'ha pogut fer la còpia de seguretat, i no s'ha desat res: \(detall)")
        case let .lectura(detall): t("no s'ha pogut llegir la configuració: \(detall)")
        case let .escriptura(detall): t("no s'ha pogut desar la configuració: \(detall)")
        case .verificacioFallida: t("la configuració generada no es podia tornar a llegir igual; no s'ha desat res")
        }
    }
}

extension Configuracio {
    /// La forma en què es desa: carpetes `~/…` expandides i opcions de Claude canòniques.
    public func normalitzada(inici: String) -> Configuracio {
        var c = self
        c.plantilla = plantilla.normalitzada()
        for f in c.finestres.indices {
            for p in c.finestres[f].pestanyes.indices {
                c.finestres[f].pestanyes[p].carpeta = Configuracio.expandeix(c.finestres[f].pestanyes[p].carpeta, inici: inici)
                c.finestres[f].pestanyes[p].claude = c.finestres[f].pestanyes[p].claude.normalitzada()
            }
        }
        return c
    }
}
