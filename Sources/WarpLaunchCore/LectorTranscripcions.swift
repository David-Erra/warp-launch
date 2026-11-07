import Foundation

/// On és la transcripció d'una conversa de Claude (`~/.claude/projects/<projecte>/<id>.jsonl`), per saber si
/// `--resume <id>` la trobarà, i quines són les converses més recents d'una carpeta (fase 3.1, D7). Només llegeix: `on`
/// només mira si el fitxer existeix, i `recents`, el principi i el final de cada transcripció.
public struct LectorTranscripcions: Sendable {
    public static let carpetaPerDefecte = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects")

    /// Claude posa un hash al nom del projecte d'una carpeta de més de 200 caràcters: llavors no es pot calcular.
    static let llargadaMaxima = 200

    public enum On: Sendable, Equatable {
        /// Al projecte de la carpeta de la pestanya (seguint l'enllaç, si el projecte ho és).
        case aLaCarpeta
        /// En altres projectes (els noms, ordenats): Claude la troba igualment (`--resume` busca a tots), però la
        /// conversa és d'una altra carpeta.
        case altres([String])
        /// Enlloc: la conversa no va arribar a tenir cap missatge, o s'ha esborrat. `--resume` sortiria amb un error.
        case enlloc
    }

    /// Una conversa que es pot reprendre, i quan se'n va escriure l'últim missatge al terminal.
    public struct Recent: Sendable, Equatable {
        public var id: String
        public var darrerMissatge: Date

        public init(id: String, darrerMissatge: Date) {
            self.id = id
            self.darrerMissatge = darrerMissatge
        }
    }

    /// Fins on es busca, des del principi, el primer missatge i la primera resposta d'una transcripció, i des del final,
    /// l'últim missatge. El 05/11/2026, el primer més tardà era als 894 KB, les transcripcions sense cap missatge
    /// feien 3 KB com a molt, i a les carpetes d'una configuració gran el darrer missatge era a 752 KB del final com a molt.
    static let maximLectura = 4 * 1024 * 1024

    public var carpeta: URL

    public init(carpeta: URL = LectorTranscripcions.carpetaPerDefecte) {
        self.carpeta = carpeta
    }

    /// El nom del projecte d'una carpeta, com el fa Claude: tot el que no és `[A-Za-z0-9]` passa a `-`. Claude ho fa en
    /// JavaScript, que compta unitats UTF-16: una lletra fora del pla bàsic (un emoji) en dona dos. `nil` si és massa
    /// llarg.
    public static func projecte(_ carpeta: String) -> String? {
        let nom = String(carpeta.utf16.map { unitat -> Character in
            switch unitat {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: Character(Unicode.Scalar(UInt8(unitat)))
            default: "-"
            }
        })
        return nom.count > llargadaMaxima ? nil : nom
    }

    /// On és la transcripció de la conversa `sessio` (un UUID) per a una pestanya de la carpeta `carpeta` (canònica).
    /// Primer, al projecte de la carpeta; si no hi és, a tots els projectes que no són enllaços (com Claude: els
    /// enllaços apunten a un altre projecte, que ja es mira). Un id que no és un UUID no es busca: `.enlloc`.
    public func on(sessio: String, carpeta: String) -> On {
        guard UUID(uuidString: sessio) != nil else { return .enlloc }
        let fitxer = sessio + ".jsonl"
        let gestor = FileManager.default
        if let projecte = Self.projecte(carpeta),
           gestor.fileExists(atPath: self.carpeta.appending(path: projecte).appending(path: fitxer).path) {
            return .aLaCarpeta
        }
        guard let projectes = try? gestor.contentsOfDirectory(atPath: self.carpeta.path) else { return .enlloc }
        let trobats = projectes.filter { projecte in
            let cami = self.carpeta.appending(path: projecte)
            var info = stat()
            guard lstat(cami.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
            return gestor.fileExists(atPath: cami.appending(path: fitxer).path)
        }
        return trobats.isEmpty ? .enlloc : .altres(trobats.sorted())
    }

    /// Les converses de la carpeta (canònica) escrites al terminal, de la més recent a la més antiga, `maxim` com a molt.
    /// Compta l'últim missatge, no la data del fitxer: Claude també l'escriu en tancar-se. No compten les transcripcions
    /// sense cap resposta de Claude, ni les de `claude -p` o d'altres apps, ni les feines en segon pla de principi a fi.
    public func recents(carpeta: String, maxim: Int = 8) -> [Recent] {
        guard let projecte = Self.projecte(carpeta) else { return [] }
        // Sense barra final, `contentsOfDirectory` no segueix el projecte si és un enllaç.
        let cami = self.carpeta.appending(path: projecte, directoryHint: .isDirectory).resolvingSymlinksInPath()
        guard let fitxers = try? FileManager.default.contentsOfDirectory(
            at: cami, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return [] }
        let candidates: [(fitxer: URL, id: String, modificat: Date)] = fitxers.compactMap { fitxer in
            let id = fitxer.deletingPathExtension().lastPathComponent
            guard fitxer.pathExtension == "jsonl", UUID(uuidString: id) != nil,
                  let valors = try? fitxer.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  valors.isRegularFile == true, let data = valors.contentModificationDate
            else { return nil }
            return (fitxer, id, data)
        }
        var trobades: [Recent] = []
        for candidata in candidates.sorted(by: { $0.modificat > $1.modificat }) {
            // Un missatge no és mai posterior a la data del fitxer: les que queden ja no poden entrar.
            if trobades.count == maxim, let darrera = trobades.last, candidata.modificat <= darrera.darrerMissatge { break }
            guard Self.esConversaDeTerminal(candidata.fitxer),
                  let data = Self.darrerMissatge(candidata.fitxer, siNoEsSap: candidata.modificat) else { continue }
            trobades.append(Recent(id: candidata.id, darrerMissatge: data))
            trobades.sort { $0.darrerMissatge > $1.darrerMissatge }
            if trobades.count > maxim { trobades.removeLast() }
        }
        return trobades
    }

    /// El primer missatge és del terminal, i Claude hi ha respost. El 05/11/2026, una bona part de les transcripcions eren de
    /// `claude -p` (`entrypoint: sdk-cli`) i unes poques de Claude Desktop, que potser encara la té oberta; i, de les més recents
    /// de cada carpeta, unes quantes no tenien cap resposta (només un `/clear`, o un «cd ..» escrit per error). Si la resposta no
    /// surt en els primers `maximLectura`, compta.
    static func esConversaDeTerminal(_ fitxer: URL) -> Bool {
        guard let lector = try? FileHandle(forReadingFrom: fitxer) else { return false }
        defer { try? lector.close() }
        var pendent = Data()
        var llegit = 0
        var delTerminal = false
        func mira(_ linia: Data) -> Bool? {
            if delTerminal { return esResposta(linia) ? true : nil }
            guard let resposta = esDeTerminal(linia: linia) else { return nil }
            if resposta { delTerminal = true; return nil }
            return false
        }
        while llegit < maximLectura, let tros = try? lector.read(upToCount: 64 * 1024), !tros.isEmpty {
            llegit += tros.count
            pendent.append(tros)
            var inici = pendent.startIndex
            while let salt = pendent[inici...].firstIndex(of: 0x0A) {
                if let resposta = mira(pendent[inici..<salt]) { return resposta }
                inici = pendent.index(after: salt)
            }
            pendent = Data(pendent[inici...])
        }
        if let resposta = mira(pendent) { return resposta }
        return delTerminal && llegit >= maximLectura
    }

    /// `nil` si la línia no és un missatge de l'usuari. Es mira el text, sense interpretar el JSON: les línies poden fer
    /// megues, i dins d'un text les cometes van escapades. Sense `entrypoint` (versions antigues de Claude), compta.
    private static func esDeTerminal(linia: Data) -> Bool? {
        guard linia.range(of: Data(#""type":"user""#.utf8)) != nil, linia.range(of: Data(#""isMeta":true"#.utf8)) == nil
        else { return nil }
        guard let origen = linia.range(of: Data(#""entrypoint":""#.utf8)) else { return true }
        return linia[origen.upperBound...].starts(with: Data(#"cli""#.utf8))
    }

    /// Una resposta de Claude. Les que escriu Claude Code sense preguntar al model (`<synthetic>`), com un error de l'API,
    /// no ho són.
    private static func esResposta(_ linia: Data) -> Bool {
        linia.range(of: Data(#""type":"assistant""#.utf8)) != nil && linia.range(of: Data(#""model":"<synthetic>""#.utf8)) == nil
    }

    /// Quan es va escriure l'últim missatge al terminal, buscant des del final. `nil` si a tot el fitxer no n'hi ha cap: una
    /// feina en segon pla (`sessionKind: bg`) de principi a fi. `siNoEsSap` si no surt en els últims `maximLectura`, o si
    /// el missatge no porta una data que s'entengui.
    ///
    /// Les línies d'una feina no compten: una conversa de terminal que després s'ha passat a segon pla és de quan se'n va
    /// escriure l'últim missatge al terminal. El 05/11/2026, una pestanya hauria passat de la seva conversa a una
    /// feina posterior. Després d'una línia de feina es continua fins on calgui: una feina de més de `maximLectura`, com
    /// una de viva de 10 MB que hi havia aquell dia, semblaria d'ara mateix.
    static func darrerMissatge(_ fitxer: URL, siNoEsSap: Date) -> Date? {
        guard let lector = try? FileHandle(forReadingFrom: fitxer), let mida = try? lector.seekToEnd() else { return siNoEsSap }
        defer { try? lector.close() }
        var fi = mida
        var pendent = Data()
        var vistaFeina = false
        func mira(_ linia: Data) -> Date?? {
            switch missatge(linia) {
            case nil: return nil
            case .deFeina:
                vistaFeina = true
                return nil
            case let .delTerminal(data): return .some(data ?? siNoEsSap)
            }
        }
        while fi > 0, vistaFeina || mida - fi < UInt64(maximLectura) {
            let inici = fi - min(fi, 64 * 1024)
            guard (try? lector.seek(toOffset: inici)) != nil,
                  let tros = try? lector.read(upToCount: Int(fi - inici)), !tros.isEmpty else { return siNoEsSap }
            pendent = tros + pendent
            fi = inici
            // De l'última línia a la primera. El que queda abans del primer salt de línia pot estar tallat: es llegeix a la
            // volta següent.
            var limit = pendent.endIndex
            while let salt = pendent[..<limit].lastIndex(of: 0x0A) {
                if let data = mira(pendent[pendent.index(after: salt)..<limit]) { return data }
                limit = salt
            }
            pendent = Data(pendent[..<limit])
        }
        guard fi == 0 else { return siNoEsSap }
        if let data = mira(pendent) { return data }
        return nil
    }

    private enum Missatge {
        case deFeina
        /// Amb la seva data, si s'entén.
        case delTerminal(Date?)
    }

    /// `nil` si la línia no és un missatge de l'usuari o de Claude. Primer es mira el text: la majoria de línies no fan falta,
    /// n'hi ha de molt grans, i una feina en pot tenir milers.
    private static func missatge(_ linia: Data) -> Missatge? {
        guard linia.range(of: Data(#""type":"user""#.utf8)) != nil || linia.range(of: Data(#""type":"assistant""#.utf8)) != nil
        else { return nil }
        if let tipusSessio = linia.range(of: Data(#""sessionKind":""#.utf8)),
           !linia[tipusSessio.upperBound...].starts(with: Data(#"interactive""#.utf8)) {
            return .deFeina
        }
        guard let objecte = (try? JSONSerialization.jsonObject(with: linia)) as? [String: Any],
              let tipus = objecte["type"] as? String, tipus == "user" || tipus == "assistant",
              objecte["isMeta"] as? Bool != true
        else { return nil }
        guard let text = objecte["timestamp"] as? String else { return .delTerminal(nil) }
        return .delTerminal(try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}
