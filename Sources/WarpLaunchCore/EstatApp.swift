import Foundation

/// El que l'app recorda de cada pestanya entre lectures (fase 3.1): el pane de Warp on és oberta i la conversa de
/// Claude que hi té, per reprendre-la (D7) i per no tornar a obrir el que ja és obert (D13, R9). També els darrers
/// llançaments.
///
/// És de l'app, no d'en David: `estat.json`, al costat de la configuració. No és a la configuració perquè canvia sol
/// (cada `/clear` dona una conversa nova) i perquè el Desfés de l'editor no l'ha de tocar.
public struct EstatApp: Sendable, Equatable {
    public static let versioActual = 1
    public static let nomFitxer = "estat.json"
    /// Llançaments que es guarden.
    public static let maxLlancaments = 20
    /// Quant es guarda l'entrada d'una pestanya que ja no és a la configuració (pel Desfés).
    public static let tempsForaDeLaConfiguracio: TimeInterval = 30 * 24 * 3600

    public var versio: Int
    public var pestanyes: [UUID: VincleEstat]
    /// Els darrers llançaments, el més antic primer.
    public var llancaments: [Llancament]

    public init(versio: Int = EstatApp.versioActual, pestanyes: [UUID: VincleEstat] = [:], llancaments: [Llancament] = []) {
        self.versio = versio
        self.pestanyes = pestanyes
        self.llancaments = llancaments
    }

    /// La conversa que reprendria la pestanya, si se sap.
    public func conversa(de pestanya: UUID) -> String? {
        pestanyes[pestanya]?.sessio
    }

    /// És la darrera conversa vista en una altra pestanya de la configuració: no es pot agafar com a «la més recent».
    public func recordadaPerUnaAltra(_ conversa: String, pestanya: UUID) -> Bool {
        pestanyes.contains { $0.key != pestanya && $0.value.sessio == conversa && $0.value.foraDesDe == nil }
    }

    /// La conversa que reprendria la pestanya, per a l'inspector i «Copia l'ordre»: la més recent de `recents`, llevat de les
    /// vives (`vives`) i de les d'altres pestanyes, o, si no n'hi ha, la darrera vista. La seva pròpia compta encara que sigui
    /// viva: la pestanya és oberta. Qui mana en obrir és el pla (`PlaObertura`), amb una lectura d'aquell moment.
    public func conversaAReprendre(de pestanya: UUID, recents: [LectorTranscripcions.Recent], vives: Set<String>) -> String? {
        let propia = conversa(de: pestanya)
        let recent = recents.first { $0.id == propia || (!vives.contains($0.id) && !recordadaPerUnaAltra($0.id, pestanya: pestanya)) }
        return recent?.id ?? propia
    }

    /// Afegeix un llançament (o en posa al dia un amb el mateix id), i en guarda els darrers `maxLlancaments`.
    public mutating func desa(_ llancament: Llancament) {
        if let i = llancaments.firstIndex(where: { $0.id == llancament.id }) {
            llancaments[i] = llancament
        } else {
            llancaments.append(llancament)
        }
        if llancaments.count > Self.maxLlancaments { llancaments.removeFirst(llancaments.count - Self.maxLlancaments) }
    }
}

/// D'on surt el lligam d'una pestanya.
public enum OrigenVincle: String, Codable, Sendable {
    /// De la importació: el pane, i la sessió si n'hi havia una de viva.
    case importacio
    /// D'un llançament confirmat: el pane de la finestra nova.
    case llancament
    /// D'una sessió de Claude amb la marca de la pestanya.
    case marca
    /// D'una sessió vista al pane de la pestanya (un `/clear` o un `/resume` fets a mà).
    case pane
}

/// El pane i la conversa d'una pestanya.
public struct VincleEstat: Codable, Sendable, Equatable {
    /// `WARP_TERMINAL_SESSION_UUID` del pane (32 xifres hexadecimals en minúscula).
    public var pane: String?
    /// La darrera conversa de Claude vista a la pestanya. Es manté quan Claude surt.
    public var sessio: String?
    /// La carpeta de la sessió quan es va veure (canònica).
    public var carpetaSessio: String?
    public var origen: OrigenVincle
    /// Quan va canviar per última vegada (a segons sencers).
    public var vista: Date
    /// Des de quan la pestanya no és a la configuració; si torna (Desfés), es treu.
    public var foraDesDe: Date?

    public init(pane: String? = nil, sessio: String? = nil, carpetaSessio: String? = nil, origen: OrigenVincle,
                vista: Date, foraDesDe: Date? = nil) {
        self.pane = pane
        self.sessio = sessio
        self.carpetaSessio = carpetaSessio
        self.origen = origen
        self.vista = ActualitzaEstat.segons(vista)
        self.foraDesDe = foraDesDe.map(ActualitzaEstat.segons)
    }
}

/// Un llançament: un fitxer temporal escrit perquè Warp obrís una finestra.
public struct Llancament: Codable, Sendable, Equatable {
    public enum Estat: String, Codable, Sendable {
        /// Escrit i demanat a Warp; encara no s'ha vist la finestra.
        case pendent
        case confirmat
        /// Als 30 s no s'havia vist la finestra.
        case senseConfirmar
        /// No s'ha pogut demanar a Warp.
        case error
    }

    public var id: UUID
    public var fitxer: String
    public var mida: Int
    public var creat: Date
    public var finestra: UUID
    public var pestanyes: [UUID]
    public var estat: Estat
    /// El fitxer temporal ja s'ha esborrat.
    public var esborrat: Bool
    /// Segons fins a la confirmació.
    public var segons: Double?

    public init(id: UUID, fitxer: String, mida: Int, creat: Date, finestra: UUID, pestanyes: [UUID], estat: Estat,
                esborrat: Bool = false, segons: Double? = nil) {
        self.id = id
        self.fitxer = fitxer
        self.mida = mida
        self.creat = ActualitzaEstat.segons(creat)
        self.finestra = finestra
        self.pestanyes = pestanyes
        self.estat = estat
        self.esborrat = esborrat
        self.segons = segons
    }
}

/// El lligam d'una pestanya importada (sense data: la posa qui la desa).
public struct VincleImportat: Sendable, Equatable {
    public var pane: String
    public var sessio: String?
    public var carpetaSessio: String?

    public init(pane: String, sessio: String? = nil, carpetaSessio: String? = nil) {
        self.pane = pane
        self.sessio = sessio
        self.carpetaSessio = carpetaSessio
    }
}

// MARK: - JSON

extension EstatApp {
    public enum ErrorEstat: Error, Equatable, CustomStringConvertible {
        /// L'ha escrit una versió més nova de l'app: no es toca, i no s'obre res.
        case versioMesNova(Int)
        case format(String)
        case lectura(String)
        case escriptura(String)

        public var description: String {
            switch self {
            case let .versioMesNova(versio):
                "«\(EstatApp.nomFitxer)» és de la versió \(versio), més nova que aquesta app (\(EstatApp.versioActual))"
            case let .format(motiu): "«\(EstatApp.nomFitxer)» no es pot llegir: \(motiu)"
            case let .lectura(motiu): "no s'ha pogut llegir «\(EstatApp.nomFitxer)»: \(motiu)"
            case let .escriptura(motiu): "no s'ha pogut desar «\(EstatApp.nomFitxer)»: \(motiu)"
            }
        }
    }

    /// La forma del fitxer: les pestanyes per id (en majúscules).
    private struct Fitxer: Codable {
        var versio: Int
        var generador: String?
        var pestanyes: [String: VincleEstat]
        var llancaments: [Llancament]
    }

    /// Llegeix el fitxer, sense escriure res: si no hi és, l'estat buit. El CLI només fa servir això.
    public static func llegeix(fitxer: URL) throws(ErrorEstat) -> EstatApp {
        let dades: Data
        do {
            dades = try Data(contentsOf: fitxer)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return EstatApp()
        } catch {
            throw .lectura(error.localizedDescription)
        }
        return try llegeix(dades)
    }

    /// Llegeix el JSON. Una versió més nova dona `versioMesNova` abans de mirar res més.
    public static func llegeix(_ dades: Data) throws(ErrorEstat) -> EstatApp {
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
        var pestanyes: [UUID: VincleEstat] = [:]
        for (clau, vincle) in fitxer.pestanyes {
            guard let id = UUID(uuidString: clau) else { throw .format("«\(clau)» no és l'id d'una pestanya") }
            pestanyes[id] = vincle
        }
        return EstatApp(versio: versio, pestanyes: pestanyes, llancaments: fitxer.llancaments)
    }

    /// El JSON, amb les claus ordenades: el mateix estat dona sempre els mateixos bytes.
    public func json(generador: String = "\(WarpLaunch.nom) \(WarpLaunch.versio)") throws -> Data {
        let fitxer = Fitxer(versio: versio, generador: generador,
                            pestanyes: Dictionary(uniqueKeysWithValues: pestanyes.map { ($0.key.uuidString, $0.value) }),
                            llancaments: llancaments)
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        codificador.dateEncodingStrategy = .iso8601
        return try codificador.encode(fitxer) + Data("\n".utf8)
    }
}

// MARK: - Posar-lo al dia

/// Les regles que posen al dia els lligams amb una lectura de Warp (docs/disseny.md, secció 7, «`estat.json`»). Pura:
/// no llegeix ni escriu res.
public enum ActualitzaEstat {
    /// Les dates de l'estat, a segons sencers: així el JSON (ISO 8601, sense fraccions) torna el mateix estat.
    public static func segons(_ data: Date) -> Date {
        Date(timeIntervalSince1970: data.timeIntervalSince1970.rounded(.down))
    }

    /// - Una sessió viva amb la marca M dona a la pestanya M la seva sessió, i el pane si és dins de Warp.
    /// - Una sessió interactiva al pane P sense marca d'una pestanya de la configuració dona la seva sessió a la pestanya
    ///   que té el pane P: així es recullen el `/clear` i el `/resume` fets a mà. Si la marca és d'una entrada que ja no
    ///   és a la configuració (s'ha tornat a importar), es posen al dia totes dues.
    /// - Si Claude surt, la sessió es manté.
    /// - Dues pestanyes de la configuració amb el mateix pane: el conserva la que ha canviat més tard.
    /// - L'entrada d'una pestanya que no és a la configuració es guarda 30 dies (`foraDesDe`), pel Desfés.
    ///
    /// Si no hi ha res nou, torna el mateix estat (i no cal desar-lo).
    public static func amb(_ lectura: LecturaWarp, configuracio: Configuracio, estat: EstatApp, ara: Date) -> EstatApp {
        let ara = segons(ara)
        var nou = estat
        let ids = Set(configuracio.finestres.flatMap(\.pestanyes).map(\.id))
        let sessions = (lectura.finestres.flatMap(\.pestanyes).flatMap(\.panes).compactMap(\.claude)
            + lectura.sessionsSensePestanya)
            .sorted { ($0.iniciada ?? .distantPast, $0.pid) < ($1.iniciada ?? .distantPast, $1.pid) }

        func posa(_ id: UUID, pane: String?, sessio: SessioClaude, origen: OrigenVincle) {
            var vincle = nou.pestanyes[id] ?? VincleEstat(origen: origen, vista: ara)
            let abans = vincle
            vincle.pane = pane
            vincle.sessio = sessio.sessionId
            vincle.carpetaSessio = sessio.carpeta
            if vincle != abans || nou.pestanyes[id] == nil {
                vincle.origen = origen
                vincle.vista = ara
            }
            nou.pestanyes[id] = vincle
        }

        for sessio in sessions {
            let pane = sessio.dinsDeWarp ? sessio.paneUUID : nil
            if let marca = sessio.marca, ids.contains(marca) {
                posa(marca, pane: pane ?? nou.pestanyes[marca]?.pane, sessio: sessio, origen: .marca)
                continue
            }
            // Una entrada de fora de la configuració (pel Desfés) segueix la seva marca.
            if let marca = sessio.marca, nou.pestanyes[marca] != nil {
                posa(marca, pane: pane ?? nou.pestanyes[marca]?.pane, sessio: sessio, origen: .marca)
            }
            if let pane,
               let id = nou.pestanyes.filter({ ids.contains($0.key) && $0.value.pane == pane })
                   .max(by: { ($0.value.vista, $0.key.uuidString) < ($1.value.vista, $1.key.uuidString) })?.key {
                posa(id, pane: pane, sessio: sessio, origen: .pane)
            }
        }

        // Un pane, una pestanya (de la configuració): el conserva la que ha canviat més tard; si és alhora, la de la
        // marca.
        let perPane = Dictionary(grouping: nou.pestanyes.filter { ids.contains($0.key) && $0.value.pane != nil },
                                 by: { $0.value.pane! })
        func ordre(_ e: (key: UUID, value: VincleEstat)) -> (Date, Int, String) {
            (e.value.vista, e.value.origen == .marca ? 1 : 0, e.key.uuidString)
        }
        for (_, entrades) in perPane where entrades.count > 1 {
            let guanyadora = entrades.max { ordre($0) < ordre($1) }!.key
            for (id, _) in entrades where id != guanyadora {
                nou.pestanyes[id]?.pane = nil
                nou.pestanyes[id]?.vista = ara
            }
        }

        // Fora de la configuració: es compta el temps, i als 30 dies es treu.
        for (id, vincle) in nou.pestanyes {
            if ids.contains(id) {
                if vincle.foraDesDe != nil { nou.pestanyes[id]?.foraDesDe = nil }
            } else if let desDe = vincle.foraDesDe {
                if ara.timeIntervalSince(desDe) > EstatApp.tempsForaDeLaConfiguracio { nou.pestanyes[id] = nil }
            } else {
                nou.pestanyes[id]?.foraDesDe = ara
            }
        }
        return nou
    }

    /// Els lligams d'una importació (en crear la configuració o tornar a importar). Una pestanya sense sessió viva
    /// hereta la de l'entrada que tenia el mateix pane, si n'hi havia.
    public static func vincula(_ vincles: [UUID: VincleImportat], estat: EstatApp, ara: Date) -> EstatApp {
        let ara = segons(ara)
        var nou = estat
        for (id, vincle) in vincles {
            let anterior = estat.pestanyes.values
                .filter { $0.pane == vincle.pane && $0.sessio != nil }
                .max { $0.vista < $1.vista }
            nou.pestanyes[id] = VincleEstat(pane: vincle.pane, sessio: vincle.sessio ?? anterior?.sessio,
                                            carpetaSessio: vincle.sessio != nil ? vincle.carpetaSessio : anterior?.carpetaSessio,
                                            origen: .importacio, vista: ara)
        }
        return nou
    }

    /// Després d'obrir una finestra: el pane de cada pestanya a la finestra nova (`Confirmacio.panes`). La conversa es
    /// manté (la de la marca ja la posa `amb`, a cada lectura). Un pane, una pestanya: si una altra el tenia, el perd.
    public static func ambPanes(_ panes: [UUID: String], estat: EstatApp, ara: Date) -> EstatApp {
        let ara = segons(ara)
        var nou = estat
        for (id, pane) in panes.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            for (altra, vincle) in nou.pestanyes where altra != id && vincle.pane == pane {
                nou.pestanyes[altra]?.pane = nil
                nou.pestanyes[altra]?.vista = ara
            }
            guard nou.pestanyes[id]?.pane != pane else { continue }
            let abans = nou.pestanyes[id]
            nou.pestanyes[id] = VincleEstat(pane: pane, sessio: abans?.sessio, carpetaSessio: abans?.carpetaSessio,
                                            origen: .llancament, vista: ara)
        }
        return nou
    }
}
