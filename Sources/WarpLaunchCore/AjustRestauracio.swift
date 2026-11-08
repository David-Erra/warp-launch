import Foundation
import os

/// Mira i canvia la línia `restore_session` de `[general]` al `settings.toml` de Warp (D19). És l'única cosa de Warp que
/// l'app pot escriure (regla 7 de CLAUDE.md). Amb la línia, fa les mateixes comprovacions que `scripts/warp-restauracio.sh`
/// (que no l'afegeix mai): si el fitxer no té exactament la forma esperada, no toca res. No hi ha ruta per defecte: la de
/// debò només la dona l'app.
///
/// **Sense la línia (0.31.2, decisió A d'en David, 08/11/2026).** Warp només escriu els ajustos que s'han canviat, i
/// `restore_session` val `true` de sèrie (docs/fets-verificats.md, 03/11/2026): qui no l'ha canviat mai no té la línia, i
/// potser ni el fitxer. Llavors el valor és el de sèrie (`Preferencies.restauracioDeSerie`), i desactivar-lo hi escriu la
/// línia: just després de la capçalera `[general]`; si no n'hi ha, la taula, abans de la primera subtaula `[general.x]` o al
/// final; i, sense el fitxer, el crea només amb això. Activar-lo no escriu res, perquè ja ho és. Tot el que és ambigu es
/// refusa sense tocar res, i la carpeta de Warp no es crea mai.
///
/// **Escriptura prudent (0.31.3, 08/11/2026).** Warp té `settings.toml` sencer a la memòria i, a cada canvi d'un ajust,
/// l'escriu sencer i no d'un sol cop: el buida i l'hi torna a escriure (docs/fets-verificats.md, 08/11/2026). Una lectura en
/// aquell moment el pot veure buit o a mitges, i escriure a partir d'aquí en perdria els altres ajustos. Per això, si el
/// fitxer ha canviat fa menys de 2 s (`segonsRecent`), no se n'analitza res ni s'hi escriu res: no és cap error, sinó
/// «torna-ho a provar més tard» (`Escriptura.mesTard`, i `valor()` torna `nil`). Un fitxer buit, igual: buit i recent pot
/// ser Warp a mig escriure; buit i antic és buit de debò, i s'hi pot escriure. L'única data recent que no compta és la del
/// fitxer que acaba de posar aquest mateix ajust, si encara és igual (`escrit`): si no, un refresc no podria tornar a
/// desactivar l'ajust fins passats 2 s, ni en sortir de l'app. I just abans del `rename`, el fitxer encara ha de ser el que
/// s'ha llegit.
public struct AjustRestauracio: Sendable {
    public struct Refusat: Error, Equatable, CustomStringConvertible {
        public var description: String
        /// No hi ha la carpeta de Warp: Warp no s'ha obert mai en aquest usuari, i no té res per restaurar. Quan la creï, la
        /// vigilància de cada minut hi afegirà la línia (`RefrescWarp.avisWarpMaiObert`).
        public var warpMaiObert = false
    }

    /// Què ha fet `posa`.
    public enum Escriptura: Equatable, Sendable {
        /// Ja tenia aquest valor: no s'hi ha escrit res.
        case jaHiEra
        case escrit
        /// `settings.toml` acaba de canviar, o ha canviat mentre es preparava el nou (Warp el podria estar escrivint): no
        /// s'hi ha escrit res. No és cap error: cal tornar-ho a provar més tard (`RefrescWarp` ho fa sense avisar).
        case mesTard
    }

    public var ruta: URL
    /// On es prepara el fitxer nou: fora de la carpeta de Warp, perquè no hi quedi res, i al mateix volum.
    public var carpetaTemporal: URL
    /// L'hora d'ara, per saber si el fitxer acaba de canviar. Les proves en donen una de fixa; l'app, la de sèrie (la guarda
    /// `lAjustDeWarpNomesLEscriuLApp` en fixa la línia).
    let rellotge: @Sendable () -> Date
    /// Només per a les proves: el que fa Warp entre la lectura i l'escriptura (escriure el fitxer, o crear-lo).
    var ganxoDeProva: (@Sendable () -> Void)?
    /// El fitxer que aquest ajust ha posat l'últim cop, compartit entre les còpies: si encara hi és igual (el mateix `stat` i
    /// el mateix contingut), la data recent és seva, i no de Warp.
    private let escrit = OSAllocatedUnfairLock<Escrit?>(initialState: nil)

    public init(ruta: URL, carpetaTemporal: URL = FileManager.default.temporaryDirectory,
                rellotge: @escaping @Sendable () -> Date = { Date() }) {
        self.ruta = ruta
        self.carpetaTemporal = carpetaTemporal
        self.rellotge = rellotge
    }

    /// La línia que s'hi escriu quan no hi és.
    static let liniaNova = "restore_session = false"

    /// Si el fitxer ha canviat fa menys d'aquesta estona, Warp el podria estar escrivint: no s'hi escriu res. Una data del
    /// futur (el rellotge del Mac ha anat enrere) també compta com a recent.
    static let segonsRecent: TimeInterval = 2

    /// El valor que fa servir Warp: el de la línia, o, sense, el de sèrie. També sense el fitxer i sense la carpeta de
    /// Warp: «Restaura Warp i surt…» llegeix el valor abans de posar-lo (`Preferencies.posaRestauracio`), i ha de poder
    /// acabar. `nil` si el fitxer acaba de canviar (`segonsRecent`): el que s'ha llegit podria ser buit o a mitges, i cal
    /// tornar-ho a mirar més tard.
    public func valor() throws(Refusat) -> Bool? {
        switch try llegeix() {
        case .senseCarpeta, .senseFitxer: Preferencies.restauracioDeSerie
        case let .fitxer(dades, text, identitat): acabaDeCanviar(identitat, dades) ? nil : try Self.analitza(text).valor
        }
    }

    /// Posa el valor. Si el fitxer acaba de canviar, o si Warp l'escriu o el crea mentrestant, no toca res i torna `.mesTard`.
    @discardableResult
    public func posa(_ nou: Bool) throws(Refusat) -> Escriptura {
        switch try llegeix() {
        case .senseCarpeta:
            guard !nou else { return .jaHiEra }
            // No es crea: seria la carpeta de Warp abans que Warp, i l'excepció de la regla 7 és només la línia.
            throw Refusat(description: "Warp encara no s'ha obert mai en aquest usuari: no hi ha la carpeta "
                + "«\(ruta.deletingLastPathComponent().path)», i Warp Launch no la crea", warpMaiObert: true)
        case .senseFitxer:
            guard !nou else { return .jaHiEra }
            return try crea(Data("[general]\n\(Self.liniaNova)\n".utf8))
        case let .fitxer(dades, text, identitat):
            // Abans d'analitzar-lo: buit o a mitges, el text no diu res de cert.
            guard !acabaDeCanviar(identitat, dades) else { return .mesTard }
            let analisi = try Self.analitza(text)
            guard analisi.valor != nou else { return .jaHiEra }
            let resultat = switch analisi.lloc {
            case let .linia(numero): Self.canvia(text, linia: numero, a: nou)
            // Sense la línia, el valor és `true`: aquí només s'hi arriba per desactivar-lo.
            case let .senseLinia(afegida): try afegida.get()
            }
            return try substitueix(dades, per: Data(resultat.utf8))
        }
    }

    /// Si el fitxer ha canviat fa menys de `segonsRecent` (també si és buit), i no és el que hi ha posat aquest ajust.
    private func acabaDeCanviar(_ identitat: Identitat, _ dades: Data) -> Bool {
        guard rellotge().timeIntervalSince(identitat.modificat) < Self.segonsRecent else { return false }
        return escrit.withLock { $0 } != Escrit(identitat: identitat, dades: dades)
    }

    // MARK: - Escriure

    /// Substitueix el fitxer d'un sol cop (`rename`), amb els permisos i els atributs estesos de l'original, si encara és
    /// el que s'ha llegit (si no, `.mesTard`).
    private func substitueix(_ dades: Data, per resultat: Data) throws(Refusat) -> Escriptura {
        var fitxer = stat(), carpeta = stat()
        guard stat(ruta.path, &fitxer) == 0, stat(carpetaTemporal.path, &carpeta) == 0 else {
            throw Refusat(description: "no es pot mirar on és «\(ruta.path)»")
        }
        // `rename` no ho miraria: un fitxer protegit no es toca.
        guard access(ruta.path, W_OK) == 0 else { throw Refusat(description: "«\(ruta.path)» és de només lectura") }
        guard fitxer.st_dev == carpeta.st_dev else {
            throw Refusat(description: "la carpeta temporal no és al mateix volum que «\(ruta.path)»")
        }
        let temporal = try prepara(resultat, permisos: Int(fitxer.st_mode & 0o7777))
        // Els atributs estesos de l'original, com `cp -p` a l'script. Si no es pot, no és motiu per aturar res.
        copyfile(ruta.path, temporal.path, nil, copyfile_flags_t(COPYFILE_XATTR))
        ganxoDeProva?()
        let nou = try identitatPreparada(temporal)
        // Warp l'escriu en calent: el que s'acaba de llegir encara ha de ser el que hi ha. Si no, Warp l'acaba d'escriure: no
        // és cap error, i es torna a provar més tard.
        guard (try? Data(contentsOf: ruta)) == dades else {
            try? FileManager.default.removeItem(at: temporal)
            return .mesTard
        }
        guard rename(temporal.path, ruta.path) == 0 else {
            let codi = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporal)
            throw Refusat(description: "no s'ha pogut escriure «\(ruta.path)»: \(codi)")
        }
        escrit.withLock { $0 = Escrit(identitat: nou, dades: resultat) }
        return .escrit
    }

    /// Crea el fitxer, que no hi era, amb 0644. Si Warp el crea mentrestant, no es trepitja: el de la carpeta temporal es
    /// posa al seu lloc d'un sol cop, i només si encara no hi ha res (si no, `EEXIST`). Crear-lo directament a la seva
    /// ruta no serviria: Warp vigila la carpeta, i en podria llegir un de buit o a mitges. Un enllaç dur deixaria un segon
    /// nom a la carpeta temporal fins a esborrar-lo, i no tots els volums en deixen fer. Si Warp l'ha creat, `.mesTard`:
    /// la propera vegada s'hi afegirà la línia, si cal, quan faci més de 2 s que ha canviat.
    private func crea(_ resultat: Data) throws(Refusat) -> Escriptura {
        var carpeta = stat(), temporals = stat()
        guard stat(ruta.deletingLastPathComponent().path, &carpeta) == 0, stat(carpetaTemporal.path, &temporals) == 0 else {
            throw Refusat(description: "no es pot mirar on és «\(ruta.path)»")
        }
        guard carpeta.st_dev == temporals.st_dev else {
            throw Refusat(description: "la carpeta temporal no és al mateix volum que «\(ruta.path)»")
        }
        let temporal = try prepara(resultat, permisos: 0o644)
        ganxoDeProva?()
        let nou = try identitatPreparada(temporal)
        guard renamex_np(temporal.path, ruta.path, UInt32(RENAME_EXCL)) == 0 else {
            let codi = errno
            try? FileManager.default.removeItem(at: temporal)
            guard codi != EEXIST else { return .mesTard }
            throw Refusat(description: "no s'ha pogut crear «\(ruta.path)»: \(String(cString: strerror(codi)))")
        }
        escrit.withLock { $0 = Escrit(identitat: nou, dades: resultat) }
        return .escrit
    }

    /// El `stat` del fitxer nou, abans de posar-lo al seu lloc: `rename` no en canvia l'inode, la mida ni la data. Després,
    /// ja podria ser el de Warp.
    private func identitatPreparada(_ temporal: URL) throws(Refusat) -> Identitat {
        var info = stat()
        guard lstat(temporal.path, &info) == 0 else {
            let codi = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: temporal)
            throw Refusat(description: "no es pot mirar el fitxer preparat: \(codi)")
        }
        return Identitat(info)
    }

    /// El fitxer nou, sencer i sincronitzat, a la carpeta temporal.
    private func prepara(_ resultat: Data, permisos: Int) throws(Refusat) -> URL {
        let temporal = carpetaTemporal.appending(path: ".warp-settings-\(UUID().uuidString).tmp")
        do {
            try EscripturaAtomica.creaFitxerNou(resultat, a: temporal, permisos: permisos)
        } catch {
            throw Refusat(description: "no s'ha pogut preparar el fitxer: \(error)")
        }
        return temporal
    }

    // MARK: - Llegir

    enum Lectura {
        /// La carpeta de Warp (la del fitxer) no hi és: Warp no s'ha obert mai en aquest usuari.
        case senseCarpeta
        /// La carpeta hi és, i el fitxer no: Warp no hi ha desat cap ajust.
        case senseFitxer
        /// La `identitat` és la de després de llegir-lo: si Warp l'ha buidat abans o durant la lectura, la data ho diu.
        case fitxer(dades: Data, text: String, identitat: Identitat)
    }

    /// El que diu `lstat` del fitxer: el volum, l'inode, la mida i la data de modificació (`st_mtimespec`). Si Warp hi
    /// escriu, canvien la data i potser la mida; si algú el substitueix, l'inode.
    struct Identitat: Equatable, Sendable {
        var volum: Int64
        var inode: UInt64
        var mida: Int64
        var segons: Int
        var nanosegons: Int

        init(_ info: stat) {
            volum = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
            mida = Int64(info.st_size)
            segons = Int(info.st_mtimespec.tv_sec)
            nanosegons = Int(info.st_mtimespec.tv_nsec)
        }

        var modificat: Date { Date(timeIntervalSince1970: TimeInterval(segons) + TimeInterval(nanosegons) / 1_000_000_000) }
    }

    /// El fitxer que ha posat aquest ajust, tal com l'ha posat.
    private struct Escrit: Equatable, Sendable {
        var identitat: Identitat
        var dades: Data
    }

    private func llegeix() throws(Refusat) -> Lectura {
        try Self.llegeix(ruta)
    }

    /// Només llegeix. També per al diagnòstic, que no pot crear l'ajust (`lAjustDeWarpNomesLEscriuLApp`): així diu el que
    /// veu l'app, i no que hi afegirà la línia si l'app no pot ni llegir el fitxer.
    static func llegeix(_ ruta: URL) throws(Refusat) -> Lectura {
        var info = stat()
        guard lstat(ruta.path, &info) == 0 else {
            let codi = errno
            guard codi == ENOENT else {
                throw Refusat(description: "no es pot mirar «\(ruta.path)»: \(String(cString: strerror(codi)))")
            }
            let carpeta = ruta.deletingLastPathComponent().path
            var infoCarpeta = stat()
            guard stat(carpeta, &infoCarpeta) == 0 else {
                let codi = errno
                guard codi == ENOENT else {
                    throw Refusat(description: "no es pot mirar «\(carpeta)»: \(String(cString: strerror(codi)))")
                }
                return .senseCarpeta
            }
            guard infoCarpeta.st_mode & S_IFMT == S_IFDIR else { throw Refusat(description: "«\(carpeta)» no és una carpeta") }
            return .senseFitxer
        }
        // `rename` substituiria l'enllaç, no el fitxer.
        guard info.st_mode & S_IFMT == S_IFREG else { throw Refusat(description: "«\(ruta.path)» no és un fitxer normal") }
        // `String(data:encoding:)` trauria la marca d'ordre de bytes (BOM) del començament, i en escriure el text es perdria:
        // el que s'escriu ha de ser el que s'ha llegit, amb només la línia canviada o afegida.
        guard let dades = try? Data(contentsOf: ruta), let text = String(validating: dades, as: UTF8.self) else {
            throw Refusat(description: "no es pot llegir «\(ruta.path)»")
        }
        // Després de llegir-lo, i no abans: si Warp l'ha buidat abans de la lectura o durant, la data ja és la d'ara.
        var despres = stat()
        guard lstat(ruta.path, &despres) == 0 else {
            throw Refusat(description: "no es pot mirar «\(ruta.path)»: \(String(cString: strerror(errno)))")
        }
        guard despres.st_mode & S_IFMT == S_IFREG else { throw Refusat(description: "«\(ruta.path)» no és un fitxer normal") }
        return .fitxer(dades: dades, text: text, identitat: Identitat(despres))
    }

    // MARK: - Analitzar

    struct Analisi: Equatable {
        /// El valor que fa servir Warp: el de la línia, o, sense, el de sèrie.
        var valor: Bool
        var lloc: Lloc
    }

    enum Lloc: Equatable {
        /// La línia hi és (la primera és la 0).
        case linia(Int)
        /// No hi és: el text amb `restore_session = false`, o per què no s'hi pot afegir.
        case senseLinia(Result<String, Refusat>)
    }

    /// Amb la línia: només una aparició a tot el fitxer, i que sigui una línia de la taula `[general]`, amb un valor `true`
    /// o `false`. Sense cap aparició, el valor de sèrie, i on s'afegiria (`afegeix`).
    static func analitza(_ text: String) throws(Refusat) -> Analisi {
        // Byte a byte: si hi és d'alguna manera, encara que un caràcter combinat l'amagués a les línies, no compta com si no.
        guard text.utf8.firstRange(of: "restore_session".utf8) != nil else {
            let afegida: Result<String, Refusat>
            do {
                afegida = .success(try afegeix(a: text))
            } catch {
                afegida = .failure(Refusat(description: "«restore_session» no hi és, i no s'hi pot afegir: \(error)"))
            }
            return Analisi(valor: Preferencies.restauracioDeSerie, lloc: .senseLinia(afegida))
        }
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
            case "true": return Analisi(valor: true, lloc: .linia(numero))
            case "false": return Analisi(valor: false, lloc: .linia(numero))
            default: throw Refusat(description: "el valor de «restore_session» no és true ni false")
            }
        }
        throw Refusat(description: "«restore_session» no és una línia de la taula [general]")
    }

    /// El text amb `restore_session = false` a la taula `[general]`, quan la línia no hi és. No és un lector de TOML: mira
    /// línia a línia, i refusa tot el que podria definir `general` d'una manera que no sap llegir, perquè una segona taula
    /// `[general]` faria el fitxer invàlid i Warp no en llegiria cap ajust.
    /// - Un fitxer buit: només la taula i la línia.
    /// - Amb una capçalera `[general]` (amb la tolerància d'espais d'`analitza`, perquè després la pugui llegir): just
    ///   després.
    /// - Sense, i amb subtaules (`[general.x]`): la taula, just abans de la primera. A TOML 1.0, definir `[general]` després
    ///   de `[general.x]` també és vàlid, però no ho era a les versions anteriors, i no se sap quin lector fa servir Warp:
    ///   abans, és vàlid a totes.
    /// - Sense cap: la taula, al final, amb una línia en blanc abans.
    private static func afegeix(a text: String) throws(Refusat) -> String {
        let taulaNova = "[general]\n\(liniaNova)\n"
        guard !text.isEmpty else { return taulaNova }
        guard !text.unicodeScalars.contains("\r") else { throw Refusat(description: "«settings.toml» té salts de línia CRLF") }
        guard text.hasSuffix("\n") else { throw Refusat(description: "«settings.toml» no acaba amb un salt de línia") }
        // Davant de la primera capçalera, no deixaria veure que és `[general]`.
        guard !text.unicodeScalars.contains("\u{FEFF}") else {
            throw Refusat(description: "«settings.toml» té una marca d'ordre de bytes (BOM)")
        }
        // Dins d'un text de diverses línies, una línia pot semblar una capçalera o una clau, i no ser-ho.
        guard !text.contains("\"\"\""), !text.contains("'''") else {
            throw Refusat(description: "«settings.toml» té textos de diverses línies («\"\"\"» o «'''»)")
        }
        var linies = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var general: [Int] = []
        var primeraSubtaula: Int?
        for (numero, linia) in linies.enumerated() {
            let sensePunta = linia.drop { $0 == " " || $0 == "\t" }
            guard sensePunta.hasPrefix("[") else {
                // `general = {…}`, `general.x = …` o `"general" = …`, a l'arrel, ja defineixen `general`. A qualsevol
                // taula: no sempre se sap on comença una taula (una llista de diverses línies també pot començar amb «[»).
                if clauDeGeneral(sensePunta) {
                    throw Refusat(description: "a la línia \(numero + 1), «general» és una clau, no una taula [general]")
                }
                continue
            }
            if linia.filter({ $0 != " " && $0 != "\t" }) == "[general]" {
                general.append(numero)
                continue
            }
            let llista = sensePunta.hasPrefix("[[")
            let clau = sensePunta.dropFirst(llista ? 2 : 1).prefix { $0 != "]" }.filter { $0 != " " && $0 != "\t" }
            let senseCometes = clau.filter { $0 != "\"" && $0 != "'" }
            // Amb una seqüència d'escapament (`["general"]`), no se sap quina clau és.
            guard senseCometes == "general" || senseCometes.hasPrefix("general.") || clau.contains("\\") else { continue }
            guard !llista, clau == senseCometes, clau != "general", !clau.contains("\\") else {
                // `[[general]]`, `["general"]` o `[general] # un comentari`, que `analitza` no veuria com a `[general]`.
                throw Refusat(description: "a la línia \(numero + 1), la taula general té una forma que Warp Launch no sap "
                    + "llegir (entre cometes, amb un comentari o com a llista de taules)")
            }
            primeraSubtaula = primeraSubtaula ?? numero
        }
        guard general.count <= 1 else {
            throw Refusat(description: "«settings.toml» té \(general.count) capçaleres [general], i n'hi hauria d'haver 1")
        }
        if let capcalera = general.first {
            linies.insert(liniaNova, at: capcalera + 1)
            return linies.joined(separator: "\n")
        }
        if let primeraSubtaula {
            linies.insert(contentsOf: ["[general]", liniaNova, ""], at: primeraSubtaula)
            return linies.joined(separator: "\n")
        }
        return text + "\n" + taulaNova
    }

    /// Si una línia que no és una capçalera dona un valor a `general` o a una clau seva (`general = …`, `general.x = …`,
    /// també entre cometes), o potser (amb una seqüència d'escapament a la clau, no se sap quina és).
    private static func clauDeGeneral(_ linia: Substring) -> Bool {
        guard let igual = linia.firstIndex(of: "=") else { return false }
        let clau = linia[..<igual].filter { $0 != " " && $0 != "\t" && $0 != "\"" && $0 != "'" }
        return clau == "general" || clau.hasPrefix("general.") || clau.contains("\\")
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
