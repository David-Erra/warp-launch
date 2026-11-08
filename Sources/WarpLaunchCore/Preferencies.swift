import Foundation

/// Les preferències de l'app: `preferencies.json`, al costat de la configuració. No són a `configuracio.json`, que és
/// d'en David i té el seu format (regla 11), ni a `estat.json`, que canvia sol.
///
/// Hi ha (D-P4, en David, 07/11/2026):
/// - el consentiment perquè l'app gestioni la restauració de sessió de Warp (D19): sense, l'app no toca Warp;
/// - el valor que tenia `restore_session` abans del primer canvi de l'app, que «Deixa de fer servir Warp Launch» torna a
///   posar (0.31.0, decisió 3 d'en David, 07/11/2026; `retornEnRetirar`).
public struct Preferencies: Sendable, Equatable {
    public static let versioActual = 1
    public static let nomFitxer = "preferencies.json"

    /// Si l'usuari ha acceptat que l'app desactivi la restauració de sessió de Warp i l'activi uns segons quan demana
    /// llegir Warp.
    public enum Consentiment: Sendable, Equatable {
        /// Encara no: l'app mostra la pantalla de consentiment i no toca Warp.
        case senseTriar
        /// Acceptat a la pantalla de consentiment, en aquesta data (a segons sencers).
        case acceptat(Date)
        /// Comptat com a acceptat sense preguntar: la carpeta ja tenia `configuracio.json` o `estat.json` (en David ja ho
        /// va decidir, D19, 05/11/2026). No se sap quan.
        case migrat
        /// Retirat amb «Deixa de fer servir Warp Launch» (0.31.0), en aquesta data (a segons sencers). Com `senseTriar`,
        /// l'app torna a preguntar i, fins llavors, no toca Warp. Però és escrit al fitxer, i el fitxer mana sobre la
        /// migració: encara que la carpeta tingui `configuracio.json`, no torna a comptar com a acceptat.
        case retirat(Date)

        public var esAcceptat: Bool {
            switch self {
            case .acceptat, .migrat: true
            case .senseTriar, .retirat: false
            }
        }

        /// Quan es va acceptar, si se sap (només amb `acceptat`). Per al diagnòstic, que no mira els casos (la guarda els
        /// deixa només en aquest fitxer).
        public var acceptatEl: Date? {
            if case let .acceptat(data) = self { data } else { nil }
        }

        /// Quan es va retirar, si s'ha retirat. Per al diagnòstic, com `acceptatEl`.
        public var retiratEl: Date? {
            if case let .retirat(data) = self { data } else { nil }
        }
    }

    /// `restore_session` com ve de sèrie a Warp: activat (en arrencar, Warp torna a obrir les finestres de l'última vegada).
    public static let restauracioDeSerie = true

    /// Què fa «Deixa de fer servir Warp Launch» amb `restore_session` (decisió 3 d'en David, 07/11/2026).
    public enum Retorn: Sendable, Equatable {
        /// El valor d'abans del primer canvi de l'app.
        case original(Bool)
        /// No se sap quin era: el de sèrie de Warp (`restauracioDeSerie`).
        case deSerie
        /// L'app no l'ha canviat mai: es queda com és.
        case senseCanvis

        /// El valor que s'hi posa; `nil`, cap.
        public var valor: Bool? {
            switch self {
            case let .original(valor): valor
            case .deSerie: Preferencies.restauracioDeSerie
            case .senseCanvis: nil
            }
        }
    }

    /// Què se'n fa de `restore_session` en deixar de fer servir l'app; `nil` sense el consentiment (l'app no l'ha tocat, o ja
    /// s'ha retirat).
    /// - Amb `acceptat`, el valor desat, que és el d'abans del primer canvi de l'app. Si no n'hi ha cap, l'app no l'ha
    ///   canviat mai: cada vegada que l'ha mirat era desactivat, i el primer canvi l'hauria desat (`posaRestauracio`).
    /// - Amb `migrat`, no se sap: el valor desat és el del primer canvi després de la 0.29.0, quan l'app ja l'havia
    ///   desactivat (D19), no el d'abans de l'app. El de sèrie de Warp.
    public var retornEnRetirar: Retorn? {
        switch restauracio {
        case .senseTriar, .retirat: nil
        case .migrat: .deSerie
        case .acceptat: restauracioOriginal.map { .original($0) } ?? .senseCanvis
        }
    }

    public var versio: Int
    public var restauracio: Consentiment
    /// `restore_session` abans del primer canvi de l'app. `nil` fins llavors.
    public var restauracioOriginal: Bool?

    public init(versio: Int = Preferencies.versioActual, restauracio: Consentiment = .senseTriar,
                restauracioOriginal: Bool? = nil) {
        self.versio = versio
        self.restauracio = restauracio
        self.restauracioOriginal = restauracioOriginal
    }
}

// MARK: - JSON

extension Preferencies {
    public enum ErrorPreferencies: Error, Equatable, CustomStringConvertible {
        /// L'ha escrit una versió més nova de l'app: no es toca.
        case versioMesNova(Int)
        case format(String)
        case lectura(String)
        case escriptura(String)

        public var description: String {
            switch self {
            case let .versioMesNova(versio):
                "«\(Preferencies.nomFitxer)» és de la versió \(versio), més nova que aquesta app (\(Preferencies.versioActual))"
            case let .format(motiu): "«\(Preferencies.nomFitxer)» no es pot llegir: \(motiu)"
            case let .lectura(motiu): "no s'ha pogut llegir «\(Preferencies.nomFitxer)»: \(motiu)"
            case let .escriptura(motiu): "no s'ha pogut desar «\(Preferencies.nomFitxer)»: \(motiu)"
            }
        }
    }

    /// La forma del fitxer.
    private struct Fitxer: Codable {
        struct Restauracio: Codable {
            /// `senseTriar`, `acceptat`, `migrat` o `retirat`.
            var consentiment: String
            /// Només amb `acceptat`.
            var acceptatEl: Date?
            /// Només amb `retirat`.
            var retiratEl: Date?
            var valorOriginal: Bool?
        }

        var versio: Int
        var generador: String?
        var restauracio: Restauracio
    }

    /// Llegeix el JSON. Una versió més nova dona `versioMesNova` abans de mirar res més.
    public static func llegeix(_ dades: Data) throws(ErrorPreferencies) -> Preferencies {
        struct NomesVersio: Decodable { var versio: Int }
        let descodificador = JSONDecoder()
        descodificador.dateDecodingStrategy = .iso8601
        guard let versio = try? descodificador.decode(NomesVersio.self, from: dades).versio else {
            throw .format("no és JSON o no té «versio»")
        }
        guard versio <= versioActual else { throw .versioMesNova(versio) }
        let fitxer: Fitxer
        do {
            fitxer = try descodificador.decode(Fitxer.self, from: dades)
        } catch {
            throw .format(String(describing: error))
        }
        let r = fitxer.restauracio
        let consentiment: Consentiment
        switch (r.consentiment, r.acceptatEl, r.retiratEl) {
        case ("senseTriar", nil, nil): consentiment = .senseTriar
        case let ("acceptat", data?, nil): consentiment = .acceptat(data)
        case ("migrat", nil, nil): consentiment = .migrat
        case let ("retirat", nil, data?): consentiment = .retirat(data)
        case ("acceptat", nil, _): throw .format("«acceptat» sense «acceptatEl»")
        case ("retirat", _, nil): throw .format("«retirat» sense «retiratEl»")
        case ("senseTriar", _, _), ("acceptat", _, _), ("migrat", _, _), ("retirat", _, _):
            throw .format("«acceptatEl» només va amb «acceptat», i «retiratEl», amb «retirat»")
        default: throw .format("«\(r.consentiment)» no és cap consentiment conegut")
        }
        return Preferencies(versio: versio, restauracio: consentiment, restauracioOriginal: r.valorOriginal)
    }

    /// El JSON, amb les claus ordenades: les mateixes preferències donen sempre els mateixos bytes.
    public func json(generador: String = "\(WarpLaunch.nom) \(WarpLaunch.versio)") throws -> Data {
        let restauracio: Fitxer.Restauracio = switch self.restauracio {
        case .senseTriar: .init(consentiment: "senseTriar", valorOriginal: restauracioOriginal)
        case let .acceptat(data): .init(consentiment: "acceptat", acceptatEl: data, valorOriginal: restauracioOriginal)
        case .migrat: .init(consentiment: "migrat", valorOriginal: restauracioOriginal)
        case let .retirat(data): .init(consentiment: "retirat", retiratEl: data, valorOriginal: restauracioOriginal)
        }
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        codificador.dateEncodingStrategy = .iso8601
        return try codificador.encode(Fitxer(versio: versio, generador: generador, restauracio: restauracio)) + Data("\n".utf8)
    }
}

// MARK: - Magatzem

/// Llegeix i desa `preferencies.json` a la carpeta de la configuració. **No té ruta per defecte**, com
/// `MagatzemConfiguracio`: l'app hi passa la seva carpeta, i les proves, una de temporal. No en fa còpies: és de l'app.
public struct MagatzemPreferencies: Sendable {
    public let carpeta: URL

    public init(carpeta: URL) {
        self.carpeta = carpeta
    }

    public var fitxer: URL { carpeta.appending(path: Preferencies.nomFitxer) }

    /// Les preferències del disc. Sense fitxer, les per defecte; però si la carpeta ja té `configuracio.json` o
    /// `estat.json`, l'app ja es feia servir abans de preguntar-ho, i el consentiment compta com a acceptat (`migrat`).
    /// **No escriu ni crea res:** el fitxer es crea quan hi ha alguna cosa a desar.
    public func carrega() throws(Preferencies.ErrorPreferencies) -> Preferencies {
        let dades: Data
        do {
            dades = try Data(contentsOf: fitxer)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Un enllaç trencat no és «no hi ha fitxer»: es desaria al damunt.
            if let desti = try? FileManager.default.destinationOfSymbolicLink(atPath: fitxer.path) {
                throw .lectura("«\(Preferencies.nomFitxer)» és un enllaç a «\(desti)», que no existeix")
            }
            return Preferencies(restauracio: jaEsFeiaServir ? .migrat : .senseTriar)
        } catch {
            throw .lectura(error.localizedDescription)
        }
        return try Preferencies.llegeix(dades)
    }

    /// Hi ha `configuracio.json` o `estat.json` (també un enllaç, encara que sigui trencat).
    private var jaEsFeiaServir: Bool {
        [MagatzemConfiguracio.nomFitxer, EstatApp.nomFitxer].contains { nom in
            var info = stat()
            return lstat(carpeta.appending(path: nom).path, &info) == 0
        }
    }

    /// Desa les preferències. Si les del disc són d'una versió més nova o no es poden llegir, no les trepitja.
    public func desa(_ preferencies: Preferencies) throws(Preferencies.ErrorPreferencies) {
        _ = try carrega()
        let dades: Data
        do {
            dades = try preferencies.json()
        } catch {
            throw .escriptura("no s'ha pogut generar el JSON: \(error)")
        }
        guard (try? Preferencies.llegeix(dades)) == preferencies else { throw .escriptura("el JSON no es torna a llegir igual") }
        do {
            try EscripturaAtomica.escriu(dades, a: fitxer)
        } catch {
            throw .escriptura(error.localizedDescription)
        }
    }

    /// «Accepta», a la pantalla de consentiment: desa el consentiment, amb la data, i en torna les preferències.
    @discardableResult
    public func accepta(ara: Date) throws(Preferencies.ErrorPreferencies) -> Preferencies {
        var preferencies = try carrega()
        preferencies.restauracio = .acceptat(Date(timeIntervalSince1970: ara.timeIntervalSince1970.rounded(.down)))
        try desa(preferencies)
        return preferencies
    }

    /// «Deixa de fer servir Warp Launch» (0.31.0): el consentiment, retirat amb la data (a segons sencers), i sense valor
    /// original, perquè si es torna a acceptar, el primer canvi de l'app desi el que hi hagi llavors. L'escriptura és
    /// atòmica: el fitxer no falta en cap moment, i la migració (que només mira si falta) no el pot tornar a donar per
    /// acceptat. Torna les preferències desades.
    @discardableResult
    public func retira(ara: Date) throws(Preferencies.ErrorPreferencies) -> Preferencies {
        var preferencies = try carrega()
        preferencies.restauracio = .retirat(Date(timeIntervalSince1970: ara.timeIntervalSince1970.rounded(.down)))
        preferencies.restauracioOriginal = nil
        try desa(preferencies)
        return preferencies
    }

    /// Desa el valor de `restore_session` d'abans del primer canvi de l'app, si encara no n'hi ha cap. Torna si l'ha desat.
    /// Sense el consentiment (tampoc retirat), res: l'app no hi toca, i el valor seria d'un canvi que no és seu.
    @discardableResult
    public func recordaRestauracioOriginal(_ valor: Bool) throws(Preferencies.ErrorPreferencies) -> Bool {
        var preferencies = try carrega()
        guard preferencies.restauracio.esAcceptat, preferencies.restauracioOriginal == nil else { return false }
        preferencies.restauracioOriginal = valor
        try desa(preferencies)
        return true
    }

    /// Canvia l'ajust de Warp (`posa`), i abans del primer canvi de l'app en desa el valor que hi havia (`valor`). Si no
    /// es pot desar, l'ajust es canvia igualment: és més important que quedi desactivat.
    public func posaRestauracio(_ nou: Bool, valor: () throws -> Bool, posa: (Bool) throws -> Void) throws {
        let actual = try valor()
        if actual != nou { _ = try? recordaRestauracioOriginal(actual) }
        try posa(nou)
    }
}
